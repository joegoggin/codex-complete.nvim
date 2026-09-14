local MiniTest = require("mini.test")
local Client = require("codex_complete.client")

local T = MiniTest.new_set()

--- Builds a command for the JSONL app-server test double.
---
---@param ... string Extra mock-server arguments.
---@return string[] command Python command and mock-server arguments.
---
local function python_command(...)
  local python = vim.fn.exepath("python3")
  if python == "" then
    python = vim.fn.exepath("python")
  end
  local command = { python, vim.fn.getcwd() .. "/tests/fixtures/mock_codex.py" }
  vim.list_extend(command, { ... })
  return command
end

T["frames fragmented JSONL responses"] = function()
  local result
  local client = Client.new({ command = "codex" })
  client.pending[7] = function(err, value)
    MiniTest.expect.equality(err, nil)
    result = value
  end
  client:_consume_stdout(nil, '{"id":7,"result":')
  client:_consume_stdout(nil, '{"ready":true}}\n')
  vim.wait(1000, function()
    return result ~= nil
  end, 5)
  MiniTest.expect.equality(result, { ready = true })
end

T["fails closed on malformed protocol output"] = function()
  local failure
  local client = Client.new({
    command = "codex",
    on_exit = function(message)
      failure = message
    end,
  })
  client:_consume_stdout(nil, "not-json\n")
  vim.wait(1000, function()
    return failure ~= nil
  end, 5)
  MiniTest.expect.equality(failure, "Codex app-server emitted invalid JSONL")
end

--- Verifies the job transport supports an authenticated JSONL subprocess.
---
--- # Example Under Test
---
--- A client is forced to use the job-based compatibility transport with the
--- Python app-server double.
---
--- # Assertions
---
--- - Client startup completes after the initialize and account requests.
--- - Subsequent JSONL requests receive their matching response.
---
T["uses the job transport for JSONL subprocesses"] = function()
  local ready
  local result
  local client = Client.new({ command = python_command() })
  client._use_jobstart = function()
    return true
  end
  client:start(function(err)
    ready = err or true
  end)
  MiniTest.expect.equality(
    vim.wait(1000, function()
      return ready ~= nil
    end, 10),
    true
  )
  MiniTest.expect.equality(ready, true)
  client:request("thread/start", {}, function(err, value)
    MiniTest.expect.equality(err, nil)
    result = value
  end)
  MiniTest.expect.equality(
    vim.wait(1000, function()
      return result ~= nil
    end, 10),
    true
  )
  MiniTest.expect.equality(result.thread.id, "thread-test")
  client:stop()
end

return T
