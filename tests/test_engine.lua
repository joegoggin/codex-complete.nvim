local MiniTest = require("mini.test")
local config = require("codex_complete.config")
local context = require("codex_complete.context")
local Engine = require("codex_complete.engine")

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      vim.cmd("enew!")
      vim.bo.filetype = "lua"
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "hello" })
      vim.api.nvim_win_set_cursor(0, { 1, 5 })
    end,
  },
})

local function python_command(...)
  local python = vim.fn.exepath("python3")
  if python == "" then
    python = vim.fn.exepath("python")
  end
  local command = { python, vim.fn.getcwd() .. "/tests/fixtures/mock_codex.py" }
  vim.list_extend(command, { ... })
  return command
end

T["completes through a real JSONL subprocess"] = function()
  local received
  local failure
  local finished = false
  local value = config.resolve({
    codex = {
      command = python_command("--expect-model", "gpt-5.6-luna", "--expect-effort", "low"),
      timeout_ms = 5000,
    },
  })
  local engine = Engine.new(value, {
    on_finished = function()
      finished = true
    end,
    on_completion = function(_, completion)
      received = completion
    end,
    on_error = function(message)
      failure = message
    end,
  })

  engine:request(context.capture(0, 0, value), true)
  vim.wait(5000, function()
    return received ~= nil or failure ~= nil
  end, 10)
  engine:stop()
  MiniTest.expect.equality(failure, nil)
  MiniTest.expect.equality(received, " world\nnext_line()")
  MiniTest.expect.equality(finished, true)
end

T["sends the configured model on completion requests"] = function()
  local received
  local failure
  local value = config.resolve({
    codex = {
      command = python_command("--expect-model", "gpt-test-fast"),
      model = "gpt-test-fast",
      timeout_ms = 5000,
    },
  })
  local engine = Engine.new(value, {
    on_completion = function(_, completion)
      received = completion
    end,
    on_error = function(message)
      failure = message
    end,
  })

  engine:request(context.capture(0, 0, value), true)
  vim.wait(5000, function()
    return received ~= nil or failure ~= nil
  end, 10)
  engine:stop()
  MiniTest.expect.equality(failure, nil)
  MiniTest.expect.equality(received, " world\nnext_line()")
end

T["sends a runtime model on later completion requests"] = function()
  local received
  local failure
  local value = config.resolve({
    codex = {
      command = python_command("--expect-model", "gpt-test-pro"),
      timeout_ms = 5000,
    },
  })
  local engine = Engine.new(value, {
    on_completion = function(_, completion)
      received = completion
    end,
    on_error = function(message)
      failure = message
    end,
  })
  engine:set_model("gpt-test-pro")

  engine:request(context.capture(0, 0, value), true)
  vim.wait(5000, function()
    return received ~= nil or failure ~= nil
  end, 10)
  engine:stop()
  MiniTest.expect.equality(failure, nil)
  MiniTest.expect.equality(received, " world\nnext_line()")
end

T["sends a runtime reasoning effort on later completion requests"] = function()
  local received
  local failure
  local value = config.resolve({
    codex = {
      command = python_command("--expect-effort", "high"),
      timeout_ms = 5000,
    },
  })
  local engine = Engine.new(value, {
    on_completion = function(_, completion)
      received = completion
    end,
    on_error = function(message)
      failure = message
    end,
  })
  engine:set_effort("high")

  engine:request(context.capture(0, 0, value), true)
  vim.wait(5000, function()
    return received ~= nil or failure ~= nil
  end, 10)
  local status = engine:status()
  engine:stop()
  MiniTest.expect.equality(failure, nil)
  MiniTest.expect.equality(received, " world\nnext_line()")
  MiniTest.expect.equality(status.effort, "high")
end

T["sends the configured default reasoning effort"] = function()
  local received
  local failure
  local value = config.resolve({
    codex = {
      command = python_command("--expect-effort", "high"),
      effort = "high",
      timeout_ms = 5000,
    },
  })
  local engine = Engine.new(value, {
    on_completion = function(_, completion)
      received = completion
    end,
    on_error = function(message)
      failure = message
    end,
  })

  engine:request(context.capture(0, 0, value), true)
  vim.wait(5000, function()
    return received ~= nil or failure ~= nil
  end, 10)
  engine:stop()
  MiniTest.expect.equality(failure, nil)
  MiniTest.expect.equality(received, " world\nnext_line()")
end

T["lists every page of visible models"] = function()
  local models
  local failure
  local value = config.resolve({ codex = { command = python_command() } })
  local engine = Engine.new(value, {})

  engine:list_models(function(err, result)
    failure = err
    models = result
  end)
  vim.wait(5000, function()
    return models ~= nil or failure ~= nil
  end, 10)
  engine:stop()

  MiniTest.expect.equality(failure, nil)
  MiniTest.expect.equality(
    vim.tbl_map(function(model)
      return model.model
    end, models),
    { "gpt-5.6-luna", "gpt-test-fast", "gpt-test-pro" }
  )
end

T["rejects malformed model lists"] = function()
  local failure
  local value = config.resolve({ codex = { command = python_command("--malformed-model-list") } })
  local engine = Engine.new(value, {})

  engine:list_models(function(err)
    failure = err
  end)
  vim.wait(5000, function()
    return failure ~= nil
  end, 10)
  engine:stop()

  MiniTest.expect.equality(failure, "Codex app-server returned an invalid model list")
end

T["reports model-list request errors"] = function()
  local failure
  local value = config.resolve({ codex = { command = python_command("--model-list-error") } })
  local engine = Engine.new(value, {})

  engine:list_models(function(err)
    failure = err
  end)
  vim.wait(5000, function()
    return failure ~= nil
  end, 10)
  engine:stop()

  MiniTest.expect.equality(failure, "Could not list Codex models: mock model list failure")
end

T["rejects model metadata without its default reasoning effort"] = function()
  local failure
  local value = config.resolve({ codex = { command = python_command("--malformed-effort-list") } })
  local engine = Engine.new(value, {})

  engine:list_models(function(err)
    failure = err
  end)
  vim.wait(5000, function()
    return failure ~= nil
  end, 10)
  engine:stop()

  MiniTest.expect.equality(failure, "Codex app-server returned an unsupported default reasoning effort")
end

T["rejects unusable reasoning-effort metadata"] = function()
  local failure
  local value = config.resolve({ codex = { command = python_command("--malformed-effort-list") } })
  local engine = Engine.new(value, {})

  engine:list_models(function(err)
    failure = err
  end)
  vim.wait(5000, function()
    return failure ~= nil
  end, 10)
  engine:stop()

  MiniTest.expect.equality(failure, "Codex app-server returned an unsupported default reasoning effort")
end

T["discards a result after cancellation"] = function()
  local received
  local finished = false
  local value = config.resolve({ codex = { command = python_command(), timeout_ms = 5000 } })
  local engine = Engine.new(value, {
    on_finished = function()
      finished = true
    end,
    on_completion = function(_, completion)
      received = completion
    end,
    on_error = function() end,
  })
  engine:request(context.capture(0, 0, value), false)
  engine:cancel()
  vim.wait(100, function()
    return false
  end, 10)
  engine:stop()
  MiniTest.expect.equality(received, nil)
  MiniTest.expect.equality(finished, true)
end

T["does not block Neovim while the server is slow"] = function()
  local command = python_command()
  command[#command + 1] = "--delay"
  local value = config.resolve({ codex = { command = command, timeout_ms = 5000 } })
  local engine = Engine.new(value, {
    on_completion = function() end,
    on_error = function() end,
  })
  local started = vim.uv.hrtime()
  engine:request(context.capture(0, 0, value), false)
  local elapsed_ms = (vim.uv.hrtime() - started) / 1000000
  engine:cancel()
  engine:stop()
  MiniTest.expect.equality(elapsed_ms < 100, true)
end

T["settles a silent request after an error"] = function()
  local command = python_command()
  command[#command + 1] = "--turn-error"
  local finished = false
  local notified_error
  local value = config.resolve({ codex = { command = command, timeout_ms = 5000 } })
  local engine = Engine.new(value, {
    on_finished = function()
      finished = true
    end,
    on_completion = function() end,
    on_error = function(message)
      notified_error = message
    end,
  })

  engine:request(context.capture(0, 0, value), false)
  vim.wait(5000, function()
    return finished
  end, 10)
  local status = engine:status()
  engine:stop()
  MiniTest.expect.equality(finished, true)
  MiniTest.expect.equality(notified_error, nil)
  MiniTest.expect.equality(status.last_error, "Could not start Codex completion: mock turn failure")
end

T["settles a silent request after a timeout"] = function()
  local command = python_command()
  command[#command + 1] = "--hang"
  local finished = false
  local notified_error
  local value = config.resolve({ codex = { command = command, timeout_ms = 1000 } })
  local engine = Engine.new(value, {
    on_finished = function()
      finished = true
    end,
    on_completion = function() end,
    on_error = function(message)
      notified_error = message
    end,
  })

  engine:request(context.capture(0, 0, value), false)
  vim.wait(2000, function()
    return finished
  end, 10)
  local status = engine:status()
  engine:stop()
  MiniTest.expect.equality(finished, true)
  MiniTest.expect.equality(notified_error, nil)
  MiniTest.expect.equality(status.last_error, "Codex completion timed out")
end

return T
