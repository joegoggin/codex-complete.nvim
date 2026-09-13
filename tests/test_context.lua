local MiniTest = require("mini.test")
local config = require("codex_complete.config")
local context = require("codex_complete.context")

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      vim.cmd("enew!")
      vim.wo.virtualedit = "onemore"
      vim.bo.buftype = ""
      vim.bo.modifiable = true
      vim.bo.readonly = false
      vim.bo.filetype = "lua"
    end,
  },
})

T["captures prefix and suffix at the byte cursor"] = function()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "local value = foobar", "return value" })
  vim.api.nvim_win_set_cursor(0, { 1, 17 })
  local result = context.capture(0, 0, config.resolve())
  MiniTest.expect.equality(result.prefix, "local value = foo")
  MiniTest.expect.equality(result.suffix, "bar\nreturn value")
end

T["captures a Tree-sitter comment as a replacement instruction"] = function()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, {
    "local user = query({",
    "  -- add query",
    "})",
    "return user",
  })
  vim.api.nvim_win_set_cursor(0, { 2, 5 })
  local result = context.capture_comment(0, 0, config.resolve())
  MiniTest.expect.equality(result.kind, "comment")
  MiniTest.expect.equality(result.instruction, "-- add query")
  MiniTest.expect.equality(result.edit, { start_row = 1, start_col = 2, end_row = 1, end_col = 14 })
  MiniTest.expect.equality(result.prefix, "local user = query({\n  ")
  MiniTest.expect.equality(result.suffix, "\n})\nreturn user")
end

T["captures an entire multiline comment node"] = function()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, {
    "local value = ",
    "--[[build a value",
    "from the input]]",
    "return value",
  })
  vim.api.nvim_win_set_cursor(0, { 3, 4 })
  local result = context.capture_comment(0, 0, config.resolve())
  MiniTest.expect.equality(result.instruction, "--[[build a value\nfrom the input]]")
  MiniTest.expect.equality(result.edit, { start_row = 1, start_col = 0, end_row = 2, end_col = 16 })
end

T["rejects comment capture away from comments"] = function()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "local value = 42" })
  vim.api.nvim_win_set_cursor(0, { 1, 6 })
  local result, err = context.capture_comment(0, 0, config.resolve())
  MiniTest.expect.equality(result, nil)
  MiniTest.expect.equality(err, "cursor is not over a comment")
end

T["reports a missing Tree-sitter parser"] = function()
  vim.bo.filetype = "codex_complete_missing_parser"
  local result, err = context.capture_comment(0, 0, config.resolve())
  MiniTest.expect.equality(result, nil)
  MiniTest.expect.equality(err, "Tree-sitter parser unavailable for this buffer")
end

T["bounds context without splitting UTF-8"] = function()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { string.rep("é", 400), string.rep("界", 400) })
  vim.api.nvim_win_set_cursor(0, { 2, 600 })
  local value = config.resolve({ context = { max_bytes = 256 } })
  local result = context.capture(0, 0, value)
  MiniTest.expect.equality(#result.prefix + #result.suffix <= 256, true)
  MiniTest.expect.equality(vim.str_utfindex(result.prefix) >= 0, true)
  MiniTest.expect.equality(vim.str_utfindex(result.suffix) >= 0, true)
end

T["allows unknown filetypes only for manual requests"] = function()
  vim.bo.filetype = "notes"
  local value = config.resolve()
  MiniTest.expect.equality(context.eligible(0, value, false), false)
  MiniTest.expect.equality(context.eligible(0, value, true), true)
end

T["always blocks sensitive filenames"] = function()
  vim.api.nvim_buf_set_name(0, "/tmp/.env.local")
  MiniTest.expect.equality(context.eligible(0, config.resolve(), true), false)
end

T["matches a cached suggestion after returning to its context"] = function()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "local value = " })
  vim.api.nvim_win_set_cursor(0, { 1, 14 })
  local value = config.resolve()
  local cached = context.capture(0, 0, value)
  vim.api.nvim_buf_set_text(0, 0, 14, 0, 14, { "x" })
  vim.api.nvim_buf_set_text(0, 0, 14, 0, 15, { "" })
  vim.api.nvim_win_set_cursor(0, { 1, 14 })
  local current = context.capture(0, 0, value)
  MiniTest.expect.equality(current.changedtick == cached.changedtick, false)
  MiniTest.expect.equality(context.cached_remainder(cached, current, "42"), "42")
end

T["returns the remainder after a matching prefix"] = function()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "local value = " })
  vim.api.nvim_win_set_cursor(0, { 1, 14 })
  local value = config.resolve()
  local cached = context.capture(0, 0, value)
  vim.api.nvim_buf_set_text(0, 0, 14, 0, 14, { "42", "pri" })
  vim.api.nvim_win_set_cursor(0, { 2, 3 })
  local current = context.capture(0, 0, value)
  MiniTest.expect.equality(context.cached_remainder(cached, current, "42\nprint(value)"), "nt(value)")
end

T["returns an empty remainder after the full suggestion is typed"] = function()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "local value = " })
  vim.api.nvim_win_set_cursor(0, { 1, 14 })
  local value = config.resolve()
  local cached = context.capture(0, 0, value)
  vim.api.nvim_buf_set_text(0, 0, 14, 0, 14, { "42" })
  vim.api.nvim_win_set_cursor(0, { 1, 16 })
  local current = context.capture(0, 0, value)
  MiniTest.expect.equality(context.cached_remainder(cached, current, "42"), "")
end

T["matches cached segments inside auto-paired delimiters"] = function()
  local cases = {
    {
      before = "pub fn mult",
      after = "pub fn multiply()",
      col = 16,
      completion = "iply(a: i32, b: i32) -> i32 {\n    a * b\n}",
      expected = "a: i32, b: i32) -> i32 {\n    a * b\n}",
      closer = ")",
    },
    {
      before = "let values = ",
      after = "let values = []",
      col = 14,
      completion = "[1, 2]",
      expected = "1, 2]",
      closer = "]",
    },
    {
      before = "fn main() ",
      after = "fn main() {}",
      col = 11,
      completion = "{\n    run();\n}",
      expected = "\n    run();\n}",
      closer = "}",
    },
  }

  for _, case in ipairs(cases) do
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { case.before })
    vim.api.nvim_win_set_cursor(0, { 1, #case.before })
    local cached = context.capture(0, 0, config.resolve())
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { case.after })
    vim.api.nvim_win_set_cursor(0, { 1, case.col })
    local current = context.capture(0, 0, config.resolve())
    local remainder, paired_delimiter = context.cached_remainder(cached, current, case.completion)
    MiniTest.expect.equality(remainder, case.expected)
    MiniTest.expect.equality(paired_delimiter, {
      closer_index = case.expected:find(case.closer, 1, true),
      replace_length = 1,
    })
  end
end

T["returns an empty remainder when an auto-pair completes the suggestion"] = function()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "call" })
  vim.api.nvim_win_set_cursor(0, { 1, 4 })
  local value = config.resolve()
  local cached = context.capture(0, 0, value)
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "call()" })
  vim.api.nvim_win_set_cursor(0, { 1, 5 })
  local current = context.capture(0, 0, value)
  MiniTest.expect.equality(context.cached_remainder(cached, current, "()"), "")
end

T["reconciles fresh completions with existing delimiters"] = function()
  local cases = {
    {
      line = "pub fn add()",
      col = 11,
      completion = "a: i32, b: i32) -> i32 {\n    a + b\n}",
      closer = ")",
    },
    {
      line = "let values = []",
      col = 14,
      completion = "1, 2]",
      closer = "]",
    },
    {
      line = "if ready {}",
      col = 10,
      completion = "\n    run();\n}",
      closer = "}",
    },
    {
      line = "call(())",
      col = 6,
      completion = "nested(value))",
      closer = ")",
      closer_index = 14,
    },
  }

  for _, case in ipairs(cases) do
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { case.line })
    vim.api.nvim_win_set_cursor(0, { 1, case.col })
    local current = context.capture(0, 0, config.resolve())
    local completion, paired_delimiter = context.reconcile_completion(current, case.completion)
    MiniTest.expect.equality(completion, case.completion)
    MiniTest.expect.equality(paired_delimiter, {
      closer_index = case.closer_index or case.completion:find(case.closer, 1, true),
      replace_length = 1,
    })
  end
end

T["leaves fresh completions without a repeated delimiter unchanged"] = function()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "call()" })
  vim.api.nvim_win_set_cursor(0, { 1, 5 })
  local current = context.capture(0, 0, config.resolve())
  local completion, paired_delimiter = context.reconcile_completion(current, "value")
  MiniTest.expect.equality(completion, "value")
  MiniTest.expect.equality(paired_delimiter, nil)
end

T["drops a fresh completion already satisfied by an auto-pair"] = function()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "call()" })
  vim.api.nvim_win_set_cursor(0, { 1, 5 })
  local current = context.capture(0, 0, config.resolve())
  MiniTest.expect.equality(context.reconcile_completion(current, ")"), "")
end

T["keeps reconciling a cached completion whose suffix already contains the closer"] = function()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "pub fn add()" })
  vim.api.nvim_win_set_cursor(0, { 1, 11 })
  local value = config.resolve()
  local cached = context.capture(0, 0, value)
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "pub fn add(a: )" })
  vim.api.nvim_win_set_cursor(0, { 1, 14 })
  local current = context.capture(0, 0, value)
  local completion = "a: i32, b: i32) -> i32 {\n    a + b\n}"
  local remainder, paired_delimiter = context.cached_remainder(cached, current, completion)
  MiniTest.expect.equality(remainder, "i32, b: i32) -> i32 {\n    a + b\n}")
  MiniTest.expect.equality(paired_delimiter, {
    closer_index = remainder:find(")", 1, true),
    replace_length = 1,
  })
end

T["rejects a mismatched auto-paired closer"] = function()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "pub fn mult" })
  vim.api.nvim_win_set_cursor(0, { 1, 11 })
  local value = config.resolve()
  local cached = context.capture(0, 0, value)
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "pub fn multiply(]" })
  vim.api.nvim_win_set_cursor(0, { 1, 16 })
  local current = context.capture(0, 0, value)
  MiniTest.expect.equality(
    context.cached_remainder(cached, current, "iply(a: i32, b: i32) -> i32 {\n    a * b\n}"),
    nil
  )
end

T["rejects nonmatching cached contexts"] = function()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "local value = ", "return value" })
  vim.api.nvim_win_set_cursor(0, { 1, 14 })
  local value = config.resolve()
  local cached = context.capture(0, 0, value)
  vim.api.nvim_buf_set_text(0, 0, 14, 0, 14, { "x" })
  vim.api.nvim_win_set_cursor(0, { 1, 15 })
  local nonmatching_prefix = context.capture(0, 0, value)
  MiniTest.expect.equality(context.cached_remainder(cached, nonmatching_prefix, "42"), nil)

  vim.api.nvim_buf_set_text(0, 0, 14, 0, 15, { "" })
  vim.api.nvim_buf_set_lines(0, 1, 2, false, { "return changed" })
  vim.api.nvim_win_set_cursor(0, { 1, 14 })
  local changed_suffix = context.capture(0, 0, value)
  MiniTest.expect.equality(context.cached_remainder(cached, changed_suffix, "42"), nil)
end

return T
