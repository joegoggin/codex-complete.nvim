--- Runs an opt-in authenticated completion smoke check.
---
--- Execute with nvim --headless -u NONE -l tests/manual_context_smoke.lua.

vim.opt.rtp:prepend(vim.fn.getcwd())
local config = require("codex_complete.config").resolve({ codex = { timeout_ms = 60000 } })
local context = require("codex_complete.context")
local Engine = require("codex_complete.engine")
local baseline = vim.env.CODEX_COMPLETE_BASELINE == "1"
if baseline then
  config.context.related.enabled = false
  local prompt = require("codex_complete.prompt")
  prompt.developer_instructions = table.concat({
    "You are an inline code completion and comment-to-code engine.",
    "Never call tools, inspect files, run commands, or ask questions.",
    "Use only the JSON context in the user message.",
    "Return a JSON object with one field named completion containing exact insertion text.",
    "Do not repeat the prefix or suffix, and do not use Markdown fences.",
    "Prefer a concise, idiomatic continuation. Return an empty string when no useful completion is clear.",
  }, " ")
end
local fixtures = {
  {
    name = "struct",
    lines = {
      "mod types;",
      "use types::MyStruct;",
      "fn main() {",
      '    let field_1 = "string_1";',
      '    let field_2 = "string_2";',
      "    let value = MyStruct {",
      "        ",
      "    };",
      "}",
    },
    cursor = { 7, 8 },
  },
  {
    name = "docs",
    lines = { "/// ", "pub struct MyStruct<'a> {", "    pub field_1: &'a str,", "    pub field_2: &'a str,", "}" },
    cursor = { 1, 4 },
  },
}
local engine = Engine.new(config, {
  on_completion = function(_, completion)
    print("COMPLETION " .. vim.json.encode(completion))
  end,
  on_error = function(message)
    print("ERROR " .. message)
  end,
})
local original = engine.client.on_notification
engine.client.on_notification = function(method, params)
  if method == "item/completed" and params.item and params.item.type == "commandExecution" then
    print("READ " .. (params.item.command or ""))
  end
  original(method, params)
end
if baseline then
  local start = engine._start_turn
  engine._start_turn = function(self, request)
    request.context.cwd = vim.fn.stdpath("cache")
    start(self, request)
  end
end
vim.api.nvim_buf_set_name(0, vim.fn.getcwd() .. "/tests/fixtures/related/smoke.rs")
vim.bo.filetype = "rust"
vim.wo.virtualedit = "onemore"
for _, fixture in ipairs(fixtures) do
  if vim.env.CODEX_COMPLETE_CASE == nil or vim.env.CODEX_COMPLETE_CASE == fixture.name then
    vim.api.nvim_buf_set_lines(0, 0, -1, false, fixture.lines)
    vim.api.nvim_win_set_cursor(0, fixture.cursor)
    print("CASE " .. fixture.name)
    engine:request(context.capture(0, 0, config), true)
    vim.wait(61000, function()
      return engine.active == nil
    end, 10)
    print(
      "TIMING " .. vim.json.encode({ duration_ms = engine:status().duration_ms, context = engine:status().context })
    )
  end
end
engine:stop()
