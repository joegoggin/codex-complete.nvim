local MiniTest = require("mini.test")
local config = require("codex_complete.config")

local T = MiniTest.new_set()

T["uses documented defaults"] = function()
  local value = config.resolve()
  MiniTest.expect.equality(value.debounce_ms, 300)
  MiniTest.expect.equality(value.loading_indicator, true)
  MiniTest.expect.equality(value.highlights.suggestion, "CodexCompleteSuggestion")
  MiniTest.expect.equality(value.highlights.background, "CodexCompleteSuggestionBackground")
  MiniTest.expect.equality(value.highlights.existing_delimiter, "MatchParen")
  MiniTest.expect.equality(value.context.max_bytes, 24 * 1024)
  MiniTest.expect.equality(value.keymaps.accept, "<M-;>")
  MiniTest.expect.equality(value.keymaps.trigger, "<M-s>")
  MiniTest.expect.equality(value.keymaps.dismiss, false)
end

T["merges nested options"] = function()
  local value = config.resolve({ context = { before_lines = 12 }, codex = { timeout_ms = 5000 } })
  MiniTest.expect.equality(value.context.before_lines, 12)
  MiniTest.expect.equality(value.context.after_lines, 50)
  MiniTest.expect.equality(value.codex.timeout_ms, 5000)
end

T["replaces configured lists"] = function()
  local value = config.resolve({ filetypes = { allow = { "lua" } }, sensitive_patterns = { "token" } })
  MiniTest.expect.equality(value.filetypes.allow, { "lua" })
  MiniTest.expect.equality(value.sensitive_patterns, { "token" })
end

T["rejects invalid limits"] = function()
  MiniTest.expect.error(function()
    config.resolve({ debounce_ms = -1 })
  end, "debounce_ms")
end

T["rejects an invalid loading indicator option"] = function()
  MiniTest.expect.error(function()
    config.resolve({ loading_indicator = "yes" })
  end, "loading_indicator")
end

T["merges and validates suggestion highlights"] = function()
  local value = config.resolve({ highlights = { background = false } })
  MiniTest.expect.equality(value.highlights.suggestion, "CodexCompleteSuggestion")
  MiniTest.expect.equality(value.highlights.background, false)
  MiniTest.expect.equality(value.highlights.existing_delimiter, "MatchParen")

  MiniTest.expect.error(function()
    config.resolve({ highlights = { suggestion = "" } })
  end, "highlights.suggestion")
  MiniTest.expect.error(function()
    config.resolve({ highlights = { background = true } })
  end, "highlights.background")
  MiniTest.expect.error(function()
    config.resolve({ highlights = { existing_delimiter = "" } })
  end, "highlights.existing_delimiter")
end

return T
