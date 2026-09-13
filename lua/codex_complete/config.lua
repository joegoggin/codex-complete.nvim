local M = {}

local defaults = {
  enabled = true,
  auto_trigger = true,
  debounce_ms = 300,
  loading_indicator = true,
  highlights = {
    suggestion = "CodexCompleteSuggestion",
    background = "CodexCompleteSuggestionBackground",
    existing_delimiter = "MatchParen",
  },
  context = {
    before_lines = 200,
    after_lines = 50,
    max_bytes = 24 * 1024,
  },
  suggestion = {
    max_lines = 20,
    max_bytes = 8 * 1024,
  },
  codex = {
    command = "codex",
    model = "gpt-5.6-luna",
    effort = "low",
    timeout_ms = 30 * 1000,
  },
  keymaps = {
    accept = "<M-;>",
    trigger = "<M-s>",
    dismiss = false,
    toggle = "<leader>at",
    select_model = "<leader>am",
    select_effort = "<leader>ar",
  },
  filetypes = {
    allow = {
      "bash",
      "c",
      "cmake",
      "cpp",
      "css",
      "cuda",
      "dart",
      "dockerfile",
      "elixir",
      "elm",
      "erlang",
      "fish",
      "go",
      "graphql",
      "haskell",
      "html",
      "java",
      "javascript",
      "javascriptreact",
      "json",
      "jsonc",
      "julia",
      "kotlin",
      "lua",
      "make",
      "nix",
      "objc",
      "ocaml",
      "perl",
      "php",
      "proto",
      "python",
      "r",
      "ruby",
      "rust",
      "scala",
      "scss",
      "sh",
      "solidity",
      "sql",
      "svelte",
      "swift",
      "terraform",
      "toml",
      "tsx",
      "typescript",
      "typescriptreact",
      "vim",
      "vue",
      "xml",
      "yaml",
      "zig",
      "zsh",
    },
    deny = {
      "gitcommit",
      "gitrebase",
      "help",
      "man",
      "markdown",
      "text",
    },
  },
  sensitive_patterns = {
    "^%.env$",
    "^%.env%.",
    "credentials",
    "secrets?%.",
    "%.key$",
    "%.pem$",
    "id_rsa",
  },
  is_eligible = nil,
  notify = true,
}

local function validate_number(name, value, minimum)
  if type(value) ~= "number" or value < minimum or value % 1 ~= 0 then
    error(("codex-complete: %s must be an integer >= %d"):format(name, minimum))
  end
end

local function validate_optional_keymap(name, value)
  if value ~= false and type(value) ~= "string" then
    error(("codex-complete: keymaps.%s must be a string or false"):format(name))
  end
end

local function validate_string_list(name, value)
  if type(value) ~= "table" then
    error(("codex-complete: %s must be a list of strings"):format(name))
  end
  for _, item in ipairs(value) do
    if type(item) ~= "string" then
      error(("codex-complete: %s must contain only strings"):format(name))
    end
  end
end

function M.resolve(opts)
  opts = opts or {}
  if type(opts) ~= "table" then
    error("codex-complete: setup options must be a table")
  end

  local value = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts)
  -- Lists are replacement values. Deep-merging array indices would leave
  -- unexpected defaults behind when users provide a shorter allowlist.
  if opts.filetypes and opts.filetypes.allow then
    value.filetypes.allow = vim.deepcopy(opts.filetypes.allow)
  end
  if opts.filetypes and opts.filetypes.deny then
    value.filetypes.deny = vim.deepcopy(opts.filetypes.deny)
  end
  if opts.sensitive_patterns then
    value.sensitive_patterns = vim.deepcopy(opts.sensitive_patterns)
  end
  validate_number("debounce_ms", value.debounce_ms, 0)
  if type(value.loading_indicator) ~= "boolean" then
    error("codex-complete: loading_indicator must be a boolean")
  end
  if type(value.highlights) ~= "table" then
    error("codex-complete: highlights must be a table")
  end
  if type(value.highlights.suggestion) ~= "string" or value.highlights.suggestion == "" then
    error("codex-complete: highlights.suggestion must be a non-empty string")
  end
  if
    value.highlights.background ~= false
    and (type(value.highlights.background) ~= "string" or value.highlights.background == "")
  then
    error("codex-complete: highlights.background must be a non-empty string or false")
  end
  if type(value.highlights.existing_delimiter) ~= "string" or value.highlights.existing_delimiter == "" then
    error("codex-complete: highlights.existing_delimiter must be a non-empty string")
  end
  validate_number("context.before_lines", value.context.before_lines, 0)
  validate_number("context.after_lines", value.context.after_lines, 0)
  validate_number("context.max_bytes", value.context.max_bytes, 256)
  validate_number("suggestion.max_lines", value.suggestion.max_lines, 1)
  validate_number("suggestion.max_bytes", value.suggestion.max_bytes, 1)
  validate_number("codex.timeout_ms", value.codex.timeout_ms, 1000)

  if type(value.codex.command) ~= "string" and type(value.codex.command) ~= "table" then
    error("codex-complete: codex.command must be a string or argv table")
  end
  if type(value.codex.command) == "table" then
    validate_string_list("codex.command", value.codex.command)
    if #value.codex.command == 0 then
      error("codex-complete: codex.command must not be empty")
    end
  elseif value.codex.command == "" then
    error("codex-complete: codex.command must not be empty")
  end
  if value.codex.model ~= nil and (type(value.codex.model) ~= "string" or value.codex.model == "") then
    error("codex-complete: codex.model must be a non-empty string or nil")
  end
  if type(value.codex.effort) ~= "string" or value.codex.effort == "" then
    error("codex-complete: codex.effort must be a non-empty string")
  end
  if value.is_eligible ~= nil and type(value.is_eligible) ~= "function" then
    error("codex-complete: is_eligible must be a function or nil")
  end
  validate_string_list("filetypes.allow", value.filetypes.allow)
  validate_string_list("filetypes.deny", value.filetypes.deny)
  validate_string_list("sensitive_patterns", value.sensitive_patterns)
  for _, pattern in ipairs(value.sensitive_patterns) do
    if not pcall(string.find, "", pattern) then
      error(("codex-complete: invalid sensitive filename pattern: %s"):format(pattern))
    end
  end

  validate_optional_keymap("accept", value.keymaps.accept)
  validate_optional_keymap("trigger", value.keymaps.trigger)
  validate_optional_keymap("dismiss", value.keymaps.dismiss)
  validate_optional_keymap("toggle", value.keymaps.toggle)
  validate_optional_keymap("select_model", value.keymaps.select_model)
  validate_optional_keymap("select_effort", value.keymaps.select_effort)
  return value
end

function M.defaults()
  return vim.deepcopy(defaults)
end

return M
