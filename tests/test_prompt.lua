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
  MiniTest.expect.equality(decoded.kind, "completion")
  MiniTest.expect.equality(decoded.prefix, "local foo")
  MiniTest.expect.equality(decoded.cursor, { line = 2, byte_column = 4 })
end

T["builds comment replacement payloads"] = function()
  local encoded = prompt.build({
    kind = "comment",
    filename = "example.lua",
    filetype = "lua",
    row = 2,
    col = 5,
    prefix = "local foo =\n  ",
    suffix = "\nreturn foo",
    instruction = "-- initialize foo",
    edit = { start_row = 1, start_col = 2, end_row = 1, end_col = 19 },
  })
  local decoded = vim.json.decode(encoded)
  MiniTest.expect.equality(decoded.kind, "comment")
  MiniTest.expect.equality(decoded.instruction, "-- initialize foo")
  MiniTest.expect.equality(decoded.replacement, {
    start = { line = 2, byte_column = 2 },
    finish = { line = 2, byte_column = 19 },
  })
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
