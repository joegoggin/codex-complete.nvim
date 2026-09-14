--- Tests bounded project context collection.
---
--- Uses Rust fixture files and controlled language-server responses.

local MiniTest = require("mini.test")
local related = require("codex_complete.related")
local context = require("codex_complete.context")
local config = require("codex_complete.config")
local T = MiniTest.new_set()

--- Captures a Rust initializer in an isolated fixture directory.
---
---@return table captured
---@return table options
---
local function fixture()
  local buf = vim.fn.bufadd(vim.fn.getcwd() .. "/tests/fixtures/related/main.rs")
  vim.api.nvim_set_current_buf(buf)
  vim.bo.modifiable = true
  vim.bo.filetype = "rust"
  vim.api.nvim_buf_set_lines(0, 0, -1, false, {
    'let field_1 = "string_1";',
    'let field_2 = "string_2";',
    "MyStruct {",
    "",
    "}",
  })
  vim.api.nvim_win_set_cursor(0, { 4, 0 })
  local options = config.resolve()
  local captured = context.capture(0, 0, options)
  return captured, options
end

--- Verifies discovery of an unopened struct and reuse of cached definitions.
---
--- # Example Under Test
---
--- A Rust initializer references a type in another file.
---
--- # Assertions
---
--- - Both fields reach the context within its configured budget.
--- - A repeated request uses the cached source.
---
T["retrieves unopened definitions and caches them"] = function()
  local captured, options = fixture()
  local finished = false
  related.collect(captured, options, function()
    finished = true
  end)
  MiniTest.expect.equality(
    vim.wait(1000, function()
      return finished
    end),
    true
  )
  local found = false
  local bytes = 0
  for _, snippet in ipairs(captured.related) do
    bytes = bytes + #snippet.text
    if snippet.filename:match("types.rs$") then
      found = snippet.text:find("pub field_1", 1, true) ~= nil and snippet.text:find("pub field_2", 1, true) ~= nil
    end
  end
  MiniTest.expect.equality(found, true)
  MiniTest.expect.equality(bytes <= options.context.related.max_bytes, true)
  local again = context.capture(0, 0, options)
  related.collect(again, options, function() end)
  MiniTest.expect.equality(again.retrieval.cache_hits > 0, true)
end

--- Verifies invalidation when an unsaved source changes.
---
--- # Example Under Test
---
--- An included type definition is edited in another buffer.
---
--- # Assertions
---
--- - Live buffer contents override disk contents.
--- - Changing the source invalidates captured dependencies.
---
T["uses unsaved definitions and invalidates dependencies"] = function()
  local captured, options = fixture()
  local buf = vim.fn.bufadd(vim.fn.getcwd() .. "/tests/fixtures/related/types.rs")
  vim.fn.bufload(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "pub struct MyStruct { pub unsaved: bool }" })
  local finished = false
  related.collect(captured, options, function()
    finished = true
  end)
  vim.wait(1000, function()
    return finished
  end)
  MiniTest.expect.equality(vim.json.encode(captured.related):find("unsaved", 1, true) ~= nil, true)
  MiniTest.expect.equality(related.valid(captured), true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "pub struct MyStruct { pub changed: bool }" })
  MiniTest.expect.equality(related.valid(captured), false)
  vim.api.nvim_buf_delete(buf, { force = true })
end

--- Verifies cancellation suppresses all late callbacks.
---
--- # Example Under Test
---
--- A pending project search is cancelled immediately.
---
--- # Assertions
---
--- - No completion callback runs after cancellation.
---
T["cancels pending retrieval"] = function()
  local captured, options = fixture()
  captured.filename = captured.filename .. ".cancel"
  local count = 0
  local cancel = related.collect(captured, options, function()
    count = count + 1
  end)
  cancel()
  vim.wait(200, function()
    return false
  end)
  MiniTest.expect.equality(count, 0)
end

--- Verifies definition links and UTF-16 request positions.
---
--- # Example Under Test
---
--- An LSP returns a definition link for an identifier after a multibyte character.
---
--- # Assertions
---
--- - The request uses the server's negotiated encoding.
--- - Definition links yield source text and unrelated roots are excluded.
---
T["normalizes LSP links and encoded positions"] = function()
  local captured, options = fixture()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "é MyStruct {", "", "}" })
  vim.api.nvim_win_set_cursor(0, { 2, 0 })
  captured = context.capture(0, 0, options)
  local original = vim.lsp.get_clients
  local position
  local root = vim.fs.normalize(vim.fn.getcwd() .. "/tests/fixtures/related")
  local client = {
    config = { root_dir = root },
    offset_encoding = "utf-16",
    supports_method = function()
      return true
    end,
    cancel_request = function() end,
    request = function(_, params, callback)
      position = params.position
      callback(nil, {
        {
          targetUri = vim.uri_from_fname(root .. "/types.rs"),
          targetRange = { start = { line = 0, character = 0 }, ["end"] = { line = 4, character = 0 } },
        },
        {
          uri = vim.uri_from_fname(vim.fn.getcwd() .. "/README.md"),
          range = { start = { line = 0, character = 0 }, ["end"] = { line = 5, character = 0 } },
        },
      })
      return true, 1
    end,
  }
  vim.lsp.get_clients = function()
    return { client }
  end
  local finished = false
  local ok, err = pcall(related.collect, captured, options, function()
    finished = true
  end)
  vim.lsp.get_clients = original
  if not ok then
    error(err)
  end
  vim.wait(1000, function()
    return finished
  end)
  MiniTest.expect.equality(position, { line = 0, character = 2 })
  MiniTest.expect.equality(captured.cwd, root)
  MiniTest.expect.equality(captured.related[1].filename, root .. "/types.rs")
  for _, snippet in ipairs(captured.related) do
    MiniTest.expect.equality(snippet.filename:find(root, 1, true) == 1, true)
  end
end

--- Verifies sensitive definitions and slow language servers degrade gracefully.
---
--- # Example Under Test
---
--- A pending definition request exceeds a short retrieval deadline.
---
--- # Assertions
---
--- - The collector completes without waiting for the language server.
--- - Sensitive source names are excluded and late replies cannot alter context.
---
T["times out and excludes sensitive sources"] = function()
  local captured, options = fixture()
  options.context.related.timeout_ms = 10
  options.sensitive_patterns = { "types", "main" }
  local original = vim.lsp.get_clients
  local reply
  vim.lsp.get_clients = function()
    return {
      {
        config = {},
        offset_encoding = "utf-8",
        supports_method = function()
          return true
        end,
        cancel_request = function() end,
        request = function(_, _, callback)
          reply = callback
          return true, 1
        end,
      },
    }
  end
  local finished = false
  local ok, err = pcall(related.collect, captured, options, function()
    finished = true
  end)
  vim.lsp.get_clients = original
  if not ok then
    error(err)
  end
  MiniTest.expect.equality(
    vim.wait(500, function()
      return finished
    end),
    true
  )
  local before = vim.json.encode(captured.related)
  reply(nil, {
    uri = vim.uri_from_fname(vim.fn.getcwd() .. "/tests/fixtures/related/types.rs"),
    range = { start = { line = 0 }, ["end"] = { line = 4 } },
  })
  MiniTest.expect.equality(vim.json.encode(captured.related), before)
  for _, snippet in ipairs(captured.related) do
    MiniTest.expect.equality(snippet.filename:match("types.rs$"), nil)
  end
end

return T
