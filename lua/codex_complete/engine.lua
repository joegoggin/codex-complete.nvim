local context = require("codex_complete.context")
local Client = require("codex_complete.client")
local prompt = require("codex_complete.prompt")

local Engine = {}
Engine.__index = Engine

function Engine.new(config, callbacks)
  local self = setmetatable({
    config = config,
    callbacks = callbacks,
    generation = 0,
    active = nil,
    last_error = nil,
  }, Engine)
  self.client = Client.new({
    command = config.codex.command,
    on_notification = function(method, params)
      self:_on_notification(method, params)
    end,
    on_exit = function(message)
      self:_fail_active(message)
    end,
  })
  return self
end

function Engine:_is_active(request)
  return self.active == request and not request.cancelled and request.generation == self.generation
end

function Engine:_finish(request, completion)
  if not self:_is_active(request) then
    return
  end
  self.active = nil
  if request.timeout then
    request.timeout:stop()
    request.timeout:close()
  end
  if self.callbacks.on_finished then
    self.callbacks.on_finished(request.context)
  end
  if completion and context.is_current(request.context) then
    self.last_error = nil
    self.callbacks.on_completion(request.context, completion)
  end
end

function Engine:_fail(request, message)
  if not self:_is_active(request) then
    return
  end
  self.active = nil
  self.last_error = message
  if request.timeout then
    request.timeout:stop()
    request.timeout:close()
  end
  if self.callbacks.on_finished then
    self.callbacks.on_finished(request.context)
  end
  if request.manual then
    self.callbacks.on_error(message)
  end
end

function Engine:_fail_active(message)
  if self.active then
    self:_fail(self.active, message)
  else
    self.last_error = message
  end
end

function Engine:_start_turn(request)
  local thread_params = {
    cwd = vim.fn.stdpath("cache"),
    ephemeral = true,
    approvalPolicy = "never",
    sandbox = "read-only",
    developerInstructions = prompt.developer_instructions,
    serviceName = "codex-complete.nvim",
  }
  if self.config.codex.model then
    thread_params.model = self.config.codex.model
  end

  self.client:request("thread/start", thread_params, function(err, result)
    if not self:_is_active(request) then
      return
    end
    if err then
      self:_fail(request, "Could not start Codex completion thread: " .. err)
      return
    end
    request.thread_id = result and result.thread and result.thread.id
    if not request.thread_id then
      self:_fail(request, "Codex app-server returned no thread id")
      return
    end

    local turn_params = {
      threadId = request.thread_id,
      input = { { type = "text", text = prompt.build(request.context) } },
      approvalPolicy = "never",
      effort = self.config.codex.effort,
      outputSchema = prompt.output_schema,
      sandboxPolicy = { type = "readOnly", networkAccess = false },
    }
    if self.config.codex.model then
      turn_params.model = self.config.codex.model
    end
    self.client:request("turn/start", turn_params, function(turn_err, turn_result)
      if not self:_is_active(request) then
        return
      end
      if turn_err then
        self:_fail(request, "Could not start Codex completion: " .. turn_err)
        return
      end
      request.turn_id = turn_result and turn_result.turn and turn_result.turn.id
      if not request.turn_id then
        self:_fail(request, "Codex app-server returned no turn id")
      end
    end)
  end)
end

function Engine:request(captured_context, manual)
  self:cancel()
  self.generation = self.generation + 1
  local request = {
    generation = self.generation,
    context = captured_context,
    manual = manual,
    message = nil,
    cancelled = false,
  }
  self.active = request

  request.timeout = vim.uv.new_timer()
  request.timeout:start(
    self.config.codex.timeout_ms,
    0,
    vim.schedule_wrap(function()
      if self:_is_active(request) then
        if request.thread_id and request.turn_id then
          self.client:request("turn/interrupt", {
            threadId = request.thread_id,
            turnId = request.turn_id,
          }, function() end)
        end
        self:_fail(request, "Codex completion timed out")
      end
    end)
  )

  self.client:start(function(err)
    if not self:_is_active(request) then
      return
    end
    if err then
      self:_fail(request, err)
      return
    end
    self:_start_turn(request)
  end)
end

function Engine:cancel()
  local request = self.active
  if not request then
    return
  end
  request.cancelled = true
  self.active = nil
  if request.timeout then
    request.timeout:stop()
    request.timeout:close()
  end
  if self.callbacks.on_finished then
    self.callbacks.on_finished(request.context)
  end
  if request.thread_id and request.turn_id and self.client.state == "ready" then
    self.client:request("turn/interrupt", {
      threadId = request.thread_id,
      turnId = request.turn_id,
    }, function() end)
  end
end

function Engine:_matches(params)
  if not self.active then
    return false
  end
  local thread_id = params.threadId or (params.turn and params.turn.threadId)
  return not thread_id or thread_id == self.active.thread_id
end

function Engine:_on_notification(method, params)
  local request = self.active
  if not request or not self:_matches(params) then
    return
  end

  if method == "item/completed" then
    local item = params.item or {}
    if item.type == "agentMessage" and item.text then
      request.message = item.text
    end
    return
  end
  if method == "item/agentMessage/delta" and params.delta then
    request.message = (request.message or "") .. params.delta
    return
  end
  if method == "turn/completed" then
    local turn = params.turn or {}
    if turn.status and turn.status ~= "completed" then
      self:_fail(request, "Codex completion ended with status " .. tostring(turn.status))
      return
    end
    local completion, parse_error = prompt.parse(request.message, self.config)
    if not completion then
      self:_fail(request, parse_error)
      return
    end
    self:_finish(request, completion)
    return
  end
  if method == "error" then
    self:_fail(request, params.message or "Codex app-server reported an error")
  end
end

function Engine:stop()
  self:cancel()
  self.client:stop()
end

function Engine:status()
  return {
    active = self.active ~= nil,
    generation = self.generation,
    last_error = self.last_error,
    client = self.client:status(),
  }
end

return Engine
