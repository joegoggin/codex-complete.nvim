local MiniTest = require("mini.test")
local config = require("codex_complete.config")
local prompt = require("codex_complete.prompt")

local T = MiniTest.new_set()

T["builds a JSON-only context payload"] = function()
  local encoded = prompt.build({
    filename = "example.lua",
    filetype = "lua",
    row = 2,
    col = 4,
    prefix = "local foo",
    suffix = "bar",
  })
  local decoded = vim.json.decode(encoded)
  MiniTest.expect.equality(decoded.prefix, "local foo")
  MiniTest.expect.equality(decoded.cursor, { line = 2, byte_column = 4 })
end

T["parses single and multiline structured output"] = function()
  local value = prompt.parse('{"completion":"bar\\nbaz"}', config.resolve())
  MiniTest.expect.equality(value, "bar\nbaz")
end

T["rejects malformed and oversized output"] = function()
  local _, malformed = prompt.parse("bar", config.resolve())
  MiniTest.expect.equality(type(malformed), "string")
  local _, oversized = prompt.parse('{"completion":"abcdef"}', config.resolve({ suggestion = { max_bytes = 3 } }))
  MiniTest.expect.equality(type(oversized), "string")
end

return T
