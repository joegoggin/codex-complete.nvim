local Client = {}
Client.__index = Client

local function command_argv(command)
  local argv
  if type(command) == "table" then
    argv = vim.deepcopy(command)
  else
    argv = { command }
  end
  vim.list_extend(argv, { "app-server", "--stdio" })
  return argv
end

function Client.new(options)
  return setmetatable({
    command = options.command,
    on_notification = options.on_notification,
    on_exit = options.on_exit,
    process = nil,
    state = "stopped",
    next_id = 1,
    pending = {},
    ready_waiters = {},
    stdout_buffer = "",
    stderr_tail = "",
    shutting_down = false,
    account = nil,
  }, Client)
end

function Client:_flush_waiters(err)
  local waiters = self.ready_waiters
  self.ready_waiters = {}
  for _, callback in ipairs(waiters) do
    callback(err)
  end
end

function Client:_fail_pending(message)
  local pending = self.pending
  self.pending = {}
  for _, callback in pairs(pending) do
    callback(message)
  end
end

function Client:_write(message)
  if not self.process then
    return false
  end
  local ok = pcall(self.process.write, self.process, vim.json.encode(message) .. "\n")
  return ok
end

function Client:notify(method, params)
  return self:_write({ method = method, params = params or {} })
end

function Client:request(method, params, callback)
  if not self.process then
    callback("Codex app-server is not running")
    return nil
  end
  local id = self.next_id
  self.next_id = id + 1
  self.pending[id] = callback
  if not self:_write({ id = id, method = method, params = params or {} }) then
    self.pending[id] = nil
    callback("Could not write to Codex app-server")
    return nil
  end
  return id
end

function Client:_handle_server_request(message)
  --- Editor-side tools and approvals are unavailable; Codex owns read-only inspection.
  self:_write({
    id = message.id,
    error = {
      code = -32601,
      message = "codex-complete does not expose tools or approvals",
    },
  })
end

function Client:_handle_message(message)
  if message.id ~= nil and (message.result ~= nil or message.error ~= nil) then
    local callback = self.pending[message.id]
    if callback then
      self.pending[message.id] = nil
      if message.error then
        callback(message.error.message or "Codex app-server request failed")
      else
        callback(nil, message.result)
      end
    end
    return
  end
  if message.id ~= nil and message.method then
    self:_handle_server_request(message)
    return
  end
  if message.method and self.on_notification then
    self.on_notification(message.method, message.params or {})
  end
end

function Client:_consume_stdout(err, chunk)
  if err then
    self.stderr_tail = tostring(err)
    return
  end
  if not chunk then
    return
  end
  self.stdout_buffer = self.stdout_buffer .. chunk
  while true do
    local newline = self.stdout_buffer:find("\n", 1, true)
    if not newline then
      break
    end
    local line = self.stdout_buffer:sub(1, newline - 1)
    self.stdout_buffer = self.stdout_buffer:sub(newline + 1)
    if line ~= "" then
      local ok, message = pcall(vim.json.decode, line)
      if ok and type(message) == "table" then
        vim.schedule(function()
          self:_handle_message(message)
        end)
      else
        vim.schedule(function()
          local protocol_error = "Codex app-server emitted invalid JSONL"
          self:_fail_pending(protocol_error)
          self:_flush_waiters(protocol_error)
          if self.on_exit then
            self.on_exit(protocol_error)
          end
          self:stop()
        end)
      end
    end
  end
end

function Client:_consume_stderr(err, chunk)
  local text = chunk or err
  if not text then
    return
  end
  self.stderr_tail = (self.stderr_tail .. tostring(text)):sub(-4096)
end

function Client:_authenticate_then_ready()
  self:request("account/read", { refreshToken = false }, function(err, result)
    if err then
      self.state = "stopped"
      self:_flush_waiters("Could not read Codex login status: " .. err)
      self:stop()
      return
    end
    local account = result and result.account or nil
    if not account or account.type ~= "chatgpt" then
      self.state = "stopped"
      self:_flush_waiters("Codex must be logged in with ChatGPT; run `codex login`")
      self:stop()
      return
    end
    self.account = account
    self.state = "ready"
    self:_flush_waiters(nil)
  end)
end

function Client:start(callback)
  if self.state == "ready" and self.process then
    callback(nil)
    return
  end
  self.ready_waiters[#self.ready_waiters + 1] = callback
  if self.state == "starting" then
    return
  end

  self.state = "starting"
  self.shutting_down = false
  self.stdout_buffer = ""
  self.stderr_tail = ""

  local ok, process_or_error = pcall(vim.system, command_argv(self.command), {
    stdin = true,
    text = true,
    stdout = function(err, data)
      self:_consume_stdout(err, data)
    end,
    stderr = function(err, data)
      self:_consume_stderr(err, data)
    end,
  }, function(result)
    vim.schedule(function()
      local was_shutting_down = self.shutting_down
      self.process = nil
      self.state = "stopped"
      local message = ("Codex app-server exited with code %d"):format(result.code or -1)
      if self.stderr_tail ~= "" then
        message = message .. ": " .. vim.trim(self.stderr_tail)
      end
      self:_fail_pending(message)
      self:_flush_waiters(message)
      if not was_shutting_down and self.on_exit then
        self.on_exit(message)
      end
    end)
  end)

  if not ok then
    self.state = "stopped"
    self:_flush_waiters("Could not start Codex app-server: " .. tostring(process_or_error))
    return
  end
  self.process = process_or_error
  self:request("initialize", {
    clientInfo = {
      name = "codex_complete_nvim",
      title = "codex-complete.nvim",
      version = "0.1.0",
    },
  }, function(err)
    if err then
      self.state = "stopped"
      self:_flush_waiters("Codex app-server initialization failed: " .. err)
      self:stop()
      return
    end
    self:notify("initialized", {})
    self:_authenticate_then_ready()
  end)
end

function Client:stop()
  self.shutting_down = true
  local process = self.process
  self.process = nil
  self.state = "stopped"
  self.account = nil
  self:_fail_pending("Codex app-server stopped")
  self:_flush_waiters("Codex app-server stopped")
  if process then
    pcall(process.write, process, nil)
    pcall(process.kill, process, 15)
  end
end

function Client:status()
  return {
    state = self.state,
    account = self.account and {
      type = self.account.type,
      planType = self.account.planType,
    } or nil,
  }
end

return Client
