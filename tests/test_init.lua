local MiniTest = require("mini.test")
local config = require("codex_complete.config")
local context = require("codex_complete.context")
local plugin = require("codex_complete")
local ui = require("codex_complete.ui")

local function python_command(...)
  local python = vim.fn.exepath("python3")
  if python == "" then
    python = vim.fn.exepath("python")
  end
  local command = { python, vim.fn.getcwd() .. "/tests/fixtures/mock_codex.py" }
  vim.list_extend(command, { ... })
  return command
end

local function setup_cached_suggestion(...)
  plugin.setup({
    auto_trigger = true,
    debounce_ms = 5000,
    codex = { command = python_command(...), timeout_ms = 5000 },
  })
  MiniTest.expect.equality(plugin.trigger({ manual = true }), true)
  MiniTest.expect.equality(
    vim.wait(5000, function()
      return plugin.status().suggestion_visible or plugin.status().engine.last_error ~= nil
    end, 10),
    true
  )
  MiniTest.expect.equality(plugin.status().engine.last_error, nil)
end

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      vim.cmd("enew!")
      vim.wo.virtualedit = "onemore"
      vim.bo.filetype = "lua"
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "local value = " })
      vim.api.nvim_win_set_cursor(0, { 1, 14 })
      plugin.setup({ auto_trigger = false })
    end,
    post_case = function()
      plugin.disable()
      ui.dismiss()
    end,
  },
})

T["installs the default accept and trigger mappings"] = function()
  MiniTest.expect.equality(vim.fn.maparg("<M-;>", "i") ~= "", true)
  MiniTest.expect.equality(vim.fn.maparg("<M-s>", "i") ~= "", true)
  MiniTest.expect.equality(vim.fn.maparg("<M-q>", "i"), "")
  MiniTest.expect.equality(vim.fn.maparg("<M-Tab>", "i"), "")
end

T["defines and restores default suggestion highlights"] = function()
  local suggestion = vim.api.nvim_get_hl(0, { name = "CodexCompleteSuggestion" })
  local background = vim.api.nvim_get_hl(0, { name = "CodexCompleteSuggestionBackground" })
  MiniTest.expect.equality(suggestion.fg, 0x000000)
  MiniTest.expect.equality(suggestion.ctermfg, 0)
  MiniTest.expect.equality(background.bg, 0x50A14F)
  MiniTest.expect.equality(background.ctermbg, 71)

  vim.api.nvim_set_hl(0, "CodexCompleteSuggestion", { fg = "#FFFFFF" })
  vim.api.nvim_set_hl(0, "CodexCompleteSuggestionBackground", { bg = "#FFFFFF" })
  vim.api.nvim_exec_autocmds("ColorScheme", {})

  suggestion = vim.api.nvim_get_hl(0, { name = "CodexCompleteSuggestion" })
  background = vim.api.nvim_get_hl(0, { name = "CodexCompleteSuggestionBackground" })
  MiniTest.expect.equality(suggestion.fg, 0x000000)
  MiniTest.expect.equality(background.bg, 0x50A14F)
end

T["dismisses a suggestion after more text is entered"] = function()
  ui.show(context.capture(0, 0, config.resolve()), "42")
  vim.api.nvim_exec_autocmds("TextChangedI", {})
  MiniTest.expect.equality(ui.current(), nil)
end

T["dismisses a suggestion after leaving insert mode"] = function()
  ui.show(context.capture(0, 0, config.resolve()), "42")
  vim.api.nvim_exec_autocmds("InsertLeave", {})
  MiniTest.expect.equality(ui.current(), nil)
end

T["shows loading until a request becomes a suggestion"] = function()
  plugin.setup({
    auto_trigger = false,
    codex = { command = python_command("--delay"), timeout_ms = 5000 },
  })
  MiniTest.expect.equality(plugin.trigger({ manual = true }), true)
  MiniTest.expect.equality(plugin.status().loading, true)
  MiniTest.expect.equality(
    vim.wait(5000, function()
      return plugin.status().suggestion_visible or plugin.status().engine.last_error ~= nil
    end, 10),
    true
  )
  MiniTest.expect.equality(plugin.status().engine.last_error, nil)
  MiniTest.expect.equality(plugin.status().loading, false)
  MiniTest.expect.equality(plugin.status().suggestion_visible, true)
end

T["clears loading when a request is cancelled"] = function()
  plugin.setup({
    auto_trigger = false,
    codex = { command = python_command("--delay"), timeout_ms = 5000 },
  })
  plugin.trigger({ manual = true })
  MiniTest.expect.equality(plugin.status().loading, true)
  vim.api.nvim_exec_autocmds("InsertLeave", {})
  MiniTest.expect.equality(plugin.status().loading, false)
  MiniTest.expect.equality(plugin.status().engine.active, false)
end

T["can disable the loading indicator"] = function()
  plugin.setup({
    auto_trigger = false,
    loading_indicator = false,
    codex = { command = python_command("--delay"), timeout_ms = 5000 },
  })
  plugin.trigger({ manual = true })
  MiniTest.expect.equality(plugin.status().loading, false)
end

T["restores a cached suggestion after typing and deleting"] = function()
  setup_cached_suggestion()
  local generation = plugin.status().engine.generation
  vim.api.nvim_buf_set_text(0, 0, 14, 0, 14, { "x" })
  vim.api.nvim_win_set_cursor(0, { 1, 15 })
  vim.api.nvim_exec_autocmds("TextChangedI", {})
  MiniTest.expect.equality(plugin.status().suggestion_visible, false)

  vim.api.nvim_buf_set_text(0, 0, 14, 0, 15, { "" })
  vim.api.nvim_win_set_cursor(0, { 1, 14 })
  vim.api.nvim_exec_autocmds("TextChangedI", {})
  MiniTest.expect.equality(ui.current().completion, " world\nnext_line()")
  MiniTest.expect.equality(plugin.status().engine.generation, generation)
end

T["shows the remainder of a cached suggestion while typing its prefix"] = function()
  setup_cached_suggestion()
  vim.api.nvim_buf_set_text(0, 0, 14, 0, 14, { " wor" })
  vim.api.nvim_win_set_cursor(0, { 1, 18 })
  vim.api.nvim_exec_autocmds("TextChangedI", {})
  MiniTest.expect.equality(ui.current().completion, "ld\nnext_line()")
end

T["restores cached text while the completion popup is visible"] = function()
  setup_cached_suggestion()
  local generation = plugin.status().engine.generation
  vim.api.nvim_buf_set_text(0, 0, 14, 0, 14, { " wor" })
  vim.api.nvim_win_set_cursor(0, { 1, 18 })
  vim.api.nvim_exec_autocmds("TextChangedP", {})
  MiniTest.expect.equality(ui.current().completion, "ld\nnext_line()")
  MiniTest.expect.equality(plugin._state.timer:is_active(), false)
  MiniTest.expect.equality(plugin.status().engine.generation, generation)
end

T["waits for a mismatch after the cached suggestion is fully typed"] = function()
  setup_cached_suggestion()
  local bufnr = vim.api.nvim_get_current_buf()
  local generation = plugin.status().engine.generation
  vim.api.nvim_buf_set_text(0, 0, 14, 0, 14, { " world", "next_line()" })
  vim.api.nvim_win_set_cursor(0, { 2, 11 })
  vim.api.nvim_exec_autocmds("TextChangedI", {})
  MiniTest.expect.equality(plugin.status().suggestion_visible, false)
  MiniTest.expect.equality(plugin._state.cache[bufnr] ~= nil, true)
  MiniTest.expect.equality(plugin._state.timer:is_active(), false)
  MiniTest.expect.equality(plugin.status().engine.generation, generation)

  vim.api.nvim_buf_set_text(0, 1, 10, 1, 11, { "" })
  vim.api.nvim_win_set_cursor(0, { 2, 10 })
  vim.api.nvim_exec_autocmds("TextChangedI", {})
  MiniTest.expect.equality(ui.current().completion, ")")
  MiniTest.expect.equality(plugin._state.timer:is_active(), false)

  vim.api.nvim_buf_set_text(0, 1, 10, 1, 10, { ")x" })
  vim.api.nvim_win_set_cursor(0, { 2, 12 })
  vim.api.nvim_exec_autocmds("TextChangedI", {})
  MiniTest.expect.equality(plugin.status().suggestion_visible, false)
  MiniTest.expect.equality(plugin._state.timer:is_active(), true)
end

T["restoring cached text cancels a newer request"] = function()
  setup_cached_suggestion("--delay")
  vim.api.nvim_buf_set_text(0, 0, 14, 0, 14, { "x" })
  vim.api.nvim_win_set_cursor(0, { 1, 15 })
  vim.api.nvim_exec_autocmds("TextChangedI", {})
  plugin.trigger({ manual = true })
  MiniTest.expect.equality(plugin.status().engine.active, true)

  vim.api.nvim_buf_set_text(0, 0, 14, 0, 15, { "" })
  vim.api.nvim_win_set_cursor(0, { 1, 14 })
  vim.api.nvim_exec_autocmds("TextChangedI", {})
  MiniTest.expect.equality(plugin.status().engine.active, false)
  MiniTest.expect.equality(ui.current().completion, " world\nnext_line()")
end

T["keeps a Rust suggestion inside an auto-paired function call"] = function()
  plugin.setup({ auto_trigger = true, debounce_ms = 5000 })
  vim.bo.filetype = "rust"
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "pub fn mult" })
  vim.api.nvim_win_set_cursor(0, { 1, 11 })
  local bufnr = vim.api.nvim_get_current_buf()
  local cached_context = context.capture(bufnr, vim.api.nvim_get_current_win(), plugin._state.config)
  plugin._state.cache[bufnr] = {
    context = cached_context,
    completion = "iply(a: i32, b: i32) -> i32 {\n    a * b\n}",
  }

  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "pub fn multiply()" })
  vim.api.nvim_win_set_cursor(0, { 1, 16 })
  vim.api.nvim_exec_autocmds("TextChangedI", {})
  MiniTest.expect.equality(ui.current().completion, "a: i32, b: i32) -> i32 {\n    a * b\n}")
  MiniTest.expect.equality(ui.current().replace_length, 1)
  MiniTest.expect.equality(plugin._state.timer:is_active(), false)
end

T["accepts the full suggestion around an auto-paired delimiter"] = function()
  plugin.setup({ auto_trigger = true, debounce_ms = 5000 })
  vim.bo.filetype = "rust"
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "pub fn mult" })
  vim.api.nvim_win_set_cursor(0, { 1, 11 })
  local bufnr = vim.api.nvim_get_current_buf()
  local cached_context = context.capture(bufnr, vim.api.nvim_get_current_win(), plugin._state.config)
  plugin._state.cache[bufnr] = {
    context = cached_context,
    completion = "iply(a: i32, b: i32) -> i32 {\n    a * b\n}",
  }
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "pub fn multiply()" })
  vim.api.nvim_win_set_cursor(0, { 1, 16 })
  vim.api.nvim_exec_autocmds("TextChangedI", {})

  MiniTest.expect.equality(plugin.accept(), true)
  MiniTest.expect.equality(vim.api.nvim_buf_get_lines(0, 0, -1, false), {
    "pub fn multiply(a: i32, b: i32) -> i32 {",
    "    a * b",
    "}",
  })
  MiniTest.expect.equality(plugin._state.cache[bufnr], nil)
end

T["reconciles and accepts a fresh suggestion around an auto-paired delimiter"] = function()
  plugin.setup({ auto_trigger = false })
  vim.bo.filetype = "rust"
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "pub fn add()" })
  vim.api.nvim_win_set_cursor(0, { 1, 11 })
  local bufnr = vim.api.nvim_get_current_buf()
  local captured = context.capture(bufnr, vim.api.nvim_get_current_win(), plugin._state.config)
  plugin._state.engine.callbacks.on_completion(captured, "a: i32, b: i32) -> i32 {\n    a + b\n}")

  MiniTest.expect.equality(ui.current().replace_length, 1)
  MiniTest.expect.equality(plugin.accept(), true)
  MiniTest.expect.equality(vim.api.nvim_buf_get_lines(0, 0, -1, false), {
    "pub fn add(a: i32, b: i32) -> i32 {",
    "    a + b",
    "}",
  })
  MiniTest.expect.equality(plugin._state.cache[bufnr], nil)
end

T["waits for another edit after accepting a suggestion"] = function()
  plugin.setup({ auto_trigger = true, debounce_ms = 5000 })
  local bufnr = vim.api.nvim_get_current_buf()
  ui.show(context.capture(bufnr, vim.api.nvim_get_current_win(), plugin._state.config), "42", {
    highlights = plugin._state.config.highlights,
  })
  MiniTest.expect.equality(plugin.accept(), true)
  local generation = plugin.status().engine.generation

  vim.api.nvim_exec_autocmds("TextChangedI", { buffer = bufnr })
  vim.api.nvim_exec_autocmds("CursorMovedI", { buffer = bufnr })
  MiniTest.expect.equality(plugin._state.timer:is_active(), false)
  MiniTest.expect.equality(plugin.status().engine.generation, generation)

  local cursor = vim.api.nvim_win_get_cursor(0)
  vim.api.nvim_buf_set_text(bufnr, cursor[1] - 1, cursor[2], cursor[1] - 1, cursor[2], { "x" })
  vim.api.nvim_win_set_cursor(0, { cursor[1], cursor[2] + 1 })
  vim.api.nvim_exec_autocmds("TextChangedI", { buffer = bufnr })
  MiniTest.expect.equality(plugin._state.timer:is_active(), true)
  MiniTest.expect.equality(plugin._state.accepted_changedtick[bufnr], nil)
end

T["allows a manual request immediately after accepting"] = function()
  plugin.setup({
    auto_trigger = true,
    debounce_ms = 5000,
    codex = { command = python_command("--delay"), timeout_ms = 5000 },
  })
  local bufnr = vim.api.nvim_get_current_buf()
  ui.show(context.capture(bufnr, vim.api.nvim_get_current_win(), plugin._state.config), "42", {
    highlights = plugin._state.config.highlights,
  })
  MiniTest.expect.equality(plugin.accept(), true)
  vim.api.nvim_exec_autocmds("TextChangedI", { buffer = bufnr })

  MiniTest.expect.equality(plugin.trigger({ manual = true }), true)
  MiniTest.expect.equality(plugin.status().engine.active, true)
end

T["clears post-acceptance suppression with its buffer"] = function()
  plugin.setup({ auto_trigger = true, debounce_ms = 5000 })
  local bufnr = vim.api.nvim_get_current_buf()
  ui.show(context.capture(bufnr, vim.api.nvim_get_current_win(), plugin._state.config), "42", {
    highlights = plugin._state.config.highlights,
  })
  MiniTest.expect.equality(plugin.accept(), true)
  MiniTest.expect.equality(plugin._state.accepted_changedtick[bufnr] ~= nil, true)

  vim.cmd("enew!")
  vim.api.nvim_buf_delete(bufnr, { force = true })
  MiniTest.expect.equality(plugin._state.accepted_changedtick[bufnr], nil)
end

T["clears cached suggestions when accepted or dismissed"] = function()
  setup_cached_suggestion()
  local bufnr = vim.api.nvim_get_current_buf()
  MiniTest.expect.equality(plugin._state.cache[bufnr] ~= nil, true)
  MiniTest.expect.equality(plugin.accept(), true)
  MiniTest.expect.equality(plugin._state.cache[bufnr], nil)

  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "local value = " })
  vim.api.nvim_win_set_cursor(0, { 1, 14 })
  setup_cached_suggestion()
  plugin.dismiss()
  MiniTest.expect.equality(plugin._state.cache[vim.api.nvim_get_current_buf()], nil)
end

T["retains cache across insert exit and clears it with the buffer"] = function()
  setup_cached_suggestion()
  local cached_bufnr = vim.api.nvim_get_current_buf()
  vim.api.nvim_exec_autocmds("InsertLeave", { buffer = cached_bufnr })
  MiniTest.expect.equality(plugin._state.cache[cached_bufnr] ~= nil, true)
  vim.cmd("enew!")
  vim.api.nvim_buf_delete(cached_bufnr, { force = true })
  MiniTest.expect.equality(plugin._state.cache[cached_bufnr], nil)
end

return T
