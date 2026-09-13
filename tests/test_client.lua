local MiniTest = require("mini.test")
local Client = require("codex_complete.client")

local T = MiniTest.new_set()

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

return T
