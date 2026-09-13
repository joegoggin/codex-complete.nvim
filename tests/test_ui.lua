local MiniTest = require("mini.test")
local config = require("codex_complete.config")
local context = require("codex_complete.context")
local ui = require("codex_complete.ui")

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      vim.cmd("enew!")
      vim.wo.virtualedit = "onemore"
      vim.bo.filetype = "lua"
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "local value = " })
      vim.api.nvim_win_set_cursor(0, { 1, 14 })
      ui.dismiss()
    end,
    post_case = ui.dismiss,
  },
})

T["renders without changing the buffer and accepts one edit"] = function()
  local captured = context.capture(0, 0, config.resolve())
  ui.show(captured, "42\nprint(value)")
  MiniTest.expect.equality(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "local value = " })
  MiniTest.expect.equality(ui.current().completion, "42\nprint(value)")
  MiniTest.expect.equality(ui.accept(), true)
  MiniTest.expect.equality(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "local value = 42", "print(value)" })
  MiniTest.expect.equality(vim.api.nvim_win_get_cursor(0), { 2, 12 })
  MiniTest.expect.equality(vim.api.nvim_buf_get_extmarks(0, -1, 0, -1, {}), {})
end

T["distinguishes suggestions from comment text"] = function()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "-- typed " })
  vim.api.nvim_win_set_cursor(0, { 1, 9 })
  local captured = context.capture(0, 0, config.resolve())
  ui.show(captured, "suggestion")

  local extmark = vim.api.nvim_buf_get_extmarks(0, -1, 0, -1, { details = true })[1]
  MiniTest.expect.equality(
    extmark[4].virt_text,
    { { "suggestion", { "CodexCompleteSuggestionBackground", "CodexCompleteSuggestion" } } }
  )
  MiniTest.expect.equality(extmark[4].hl_mode, "replace")
  MiniTest.expect.equality(extmark[4].line_hl_group, nil)
  ui.dismiss()
  MiniTest.expect.equality(vim.api.nvim_buf_get_extmarks(0, -1, 0, -1, {}), {})
end

T["supports custom suggestion highlights without a background"] = function()
  local captured = context.capture(0, 0, config.resolve())
  ui.show(captured, "42\nprint(value)", {
    highlights = { suggestion = "Special", background = false },
  })

  local extmark = vim.api.nvim_buf_get_extmarks(0, -1, 0, -1, { details = true })[1]
  MiniTest.expect.equality(extmark[4].virt_text, { { "42", "Special" } })
  MiniTest.expect.equality(extmark[4].virt_lines, { { { "print(value)", "Special" } } })
  MiniTest.expect.equality(extmark[4].line_hl_group, nil)
end

T["refuses a stale suggestion"] = function()
  local captured = context.capture(0, 0, config.resolve())
  ui.show(captured, "42")
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "changed" })
  MiniTest.expect.equality(ui.accept(), false)
end

T["places the cursor after a single-line insertion"] = function()
  local captured = context.capture(0, 0, config.resolve())
  ui.show(captured, "42")
  MiniTest.expect.equality(ui.accept(), true)
  MiniTest.expect.equality(vim.api.nvim_win_get_cursor(0), { 1, 16 })
end

T["previews and accepts a comment replacement"] = function()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "local value = ", "  -- build value", "return value" })
  vim.api.nvim_win_set_cursor(0, { 2, 5 })
  local captured = {
    kind = "comment",
    bufnr = 0,
    winid = 0,
    row = 2,
    col = 5,
    changedtick = vim.api.nvim_buf_get_changedtick(0),
    edit = { start_row = 1, start_col = 2, end_row = 1, end_col = 16 },
  }
  ui.show_replacement(captured, "make_value(\n  source\n)")

  MiniTest.expect.equality(
    vim.api.nvim_buf_get_lines(0, 0, -1, false),
    { "local value = ", "  -- build value", "return value" }
  )
  local extmark = vim.api.nvim_buf_get_extmarks(0, -1, 0, -1, { details = true })[1]
  MiniTest.expect.equality(extmark[2], 1)
  MiniTest.expect.equality(extmark[4].virt_lines, {
    {
      { "  ", "Normal" },
      { "make_value(", { "CodexCompleteSuggestionBackground", "CodexCompleteSuggestion" } },
    },
    { { "  source", { "CodexCompleteSuggestionBackground", "CodexCompleteSuggestion" } } },
    { { ")", { "CodexCompleteSuggestionBackground", "CodexCompleteSuggestion" } } },
  })

  MiniTest.expect.equality(ui.accept(), true)
  MiniTest.expect.equality(
    vim.api.nvim_buf_get_lines(0, 0, -1, false),
    { "local value = ", "  make_value(", "  source", ")", "return value" }
  )
  MiniTest.expect.equality(vim.api.nvim_win_get_cursor(0), { 4, 1 })
end

T["refuses a stale comment replacement"] = function()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "-- build value" })
  vim.api.nvim_win_set_cursor(0, { 1, 3 })
  local captured = {
    kind = "comment",
    bufnr = 0,
    winid = 0,
    row = 1,
    col = 3,
    changedtick = vim.api.nvim_buf_get_changedtick(0),
    edit = { start_row = 0, start_col = 0, end_row = 0, end_col = 14 },
  }
  ui.show_replacement(captured, "make_value()")
  vim.api.nvim_win_set_cursor(0, { 1, 4 })
  MiniTest.expect.equality(ui.accept(), false)
  MiniTest.expect.equality(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "-- build value" })
end

T["renders and accepts a completion around an existing delimiter"] = function()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "call()" })
  vim.api.nvim_win_set_cursor(0, { 1, 5 })
  local captured = context.capture(0, 0, config.resolve())
  ui.show(captured, "value) -> result\nnext()", {
    paired_delimiter = { closer_index = 6, replace_length = 1 },
  })

  local extmarks = vim.api.nvim_buf_get_extmarks(0, -1, 0, -1, { details = true })
  MiniTest.expect.equality(#extmarks, 2)
  MiniTest.expect.equality(extmarks[1][3], 5)
  MiniTest.expect.equality(
    extmarks[1][4].virt_text,
    { { "value", { "CodexCompleteSuggestionBackground", "CodexCompleteSuggestion" } } }
  )
  MiniTest.expect.equality(extmarks[1][4].hl_mode, "replace")
  MiniTest.expect.equality(extmarks[1][4].line_hl_group, nil)
  MiniTest.expect.equality(extmarks[2][3], 6)
  MiniTest.expect.equality(
    extmarks[2][4].virt_text,
    { { " -> result", { "CodexCompleteSuggestionBackground", "CodexCompleteSuggestion" } } }
  )
  MiniTest.expect.equality(extmarks[2][4].hl_mode, "replace")
  MiniTest.expect.equality(extmarks[2][4].line_hl_group, nil)
  MiniTest.expect.equality(
    extmarks[2][4].virt_lines,
    { { { "next()", { "CodexCompleteSuggestionBackground", "CodexCompleteSuggestion" } } } }
  )

  MiniTest.expect.equality(ui.accept(), true)
  MiniTest.expect.equality(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "call(value) -> result", "next()" })
end

T["moves existing closers to the end of multiline previews"] = function()
  local cases = {
    {
      line = "fn main() {}",
      col = 11,
      completion = "\n    run();\n}",
      closer = "}",
      expected = { "fn main() {", "    run();", "}" },
    },
    {
      line = "let values = []",
      col = 14,
      completion = "1,\n  2]",
      closer = "]",
      expected = { "let values = [1,", "  2]" },
    },
  }

  for _, case in ipairs(cases) do
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { case.line })
    vim.api.nvim_win_set_cursor(0, { 1, case.col })
    local captured = context.capture(0, 0, config.resolve())
    ui.show(captured, case.completion, {
      paired_delimiter = {
        closer_index = case.completion:find(case.closer, 1, true),
        replace_length = 1,
      },
    })

    MiniTest.expect.equality(vim.api.nvim_buf_get_lines(0, 0, -1, false), { case.line })
    local extmarks = vim.api.nvim_buf_get_extmarks(0, -1, 0, -1, { details = true })
    MiniTest.expect.equality(#extmarks, 2)
    MiniTest.expect.equality(extmarks[1][4].virt_text_pos, "inline")
    local final_line = extmarks[1][4].virt_lines[#extmarks[1][4].virt_lines]
    MiniTest.expect.equality(final_line[#final_line], { case.closer, "MatchParen" })
    local suggestion_line = #final_line > 1 and final_line or extmarks[1][4].virt_lines[#extmarks[1][4].virt_lines - 1]
    MiniTest.expect.equality(suggestion_line[1][2], { "CodexCompleteSuggestionBackground", "CodexCompleteSuggestion" })
    MiniTest.expect.equality(extmarks[2][4].virt_text, { { " ", "Normal" } })
    MiniTest.expect.equality(extmarks[2][4].virt_text_pos, "overlay")
    MiniTest.expect.equality(extmarks[2][4].priority, 5000)

    MiniTest.expect.equality(ui.accept(), true)
    MiniTest.expect.equality(vim.api.nvim_buf_get_lines(0, 0, -1, false), case.expected)
    MiniTest.expect.equality(vim.api.nvim_buf_get_extmarks(0, -1, 0, -1, {}), {})
  end
end

T["animates loading text without changing the buffer"] = function()
  local captured = context.capture(0, 0, config.resolve())
  ui.show_loading(captured)
  local first_frame = ui.loading().frame
  local extmarks = vim.api.nvim_buf_get_extmarks(0, -1, 0, -1, { details = true })
  MiniTest.expect.equality(#extmarks, 1)
  MiniTest.expect.equality(extmarks[1][4].virt_text, { { "  ⠋", "DiagnosticHint" } })
  MiniTest.expect.equality(ui.current(), nil)
  MiniTest.expect.equality(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "local value = " })
  MiniTest.expect.equality(
    vim.wait(500, function()
      return ui.loading() and ui.loading().frame ~= first_frame
    end, 10),
    true
  )
end

T["replaces loading text with a suggestion"] = function()
  local captured = context.capture(0, 0, config.resolve())
  ui.show_loading(captured)
  ui.show(captured, "42")
  MiniTest.expect.equality(ui.loading(), nil)
  MiniTest.expect.equality(ui.current().completion, "42")
end

return T
