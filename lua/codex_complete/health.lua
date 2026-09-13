local M = {}

local function command_name(command)
  if type(command) == "table" then
    return command[1]
  end
  return command
end

local function command_argv(command, arguments)
  local result = type(command) == "table" and vim.deepcopy(command) or { command }
  vim.list_extend(result, arguments)
  return result
end

function M.check()
  vim.health.start("codex-complete.nvim")

  if vim.fn.has("nvim-0.10") == 1 then
    vim.health.ok("Neovim 0.10 or newer")
  else
    vim.health.error("Neovim 0.10 or newer is required")
  end

  local ok, plugin = pcall(require, "codex_complete")
  local configured = ok and plugin.status().configured
  local config = configured and plugin._state.config or require("codex_complete.config").defaults()
  local executable = command_name(config.codex.command)
  if vim.fn.executable(executable) ~= 1 then
    vim.health.error(("Codex CLI executable not found: %s"):format(executable))
    return
  end
  vim.health.ok(("Codex CLI executable found: %s"):format(executable))

  local version = vim.system(command_argv(config.codex.command, { "--version" }), { text = true }):wait(5000)
  if version.code == 0 then
    vim.health.info(vim.trim(version.stdout or "Codex CLI version unavailable"))
  else
    vim.health.warn("Could not determine the Codex CLI version")
  end

  local login = vim.system(command_argv(config.codex.command, { "login", "status" }), { text = true }):wait(5000)
  local login_text = vim.trim((login.stdout or "") .. "\n" .. (login.stderr or ""))
  if login.code ~= 0 then
    vim.health.error("Codex is not authenticated; run `codex login`")
  elseif not login_text:lower():find("chatgpt", 1, true) then
    vim.health.error("Codex is not using ChatGPT subscription authentication; run `codex login`")
  else
    vim.health.ok("Codex is authenticated with ChatGPT")
  end

  local app_server =
    vim.system(command_argv(config.codex.command, { "app-server", "--help" }), { text = true }):wait(5000)
  if app_server.code == 0 then
    vim.health.ok("Codex app-server is available")
  else
    vim.health.error("This Codex CLI does not provide a compatible app-server command")
  end

  if not configured then
    vim.health.warn("Plugin is not configured; call require('codex_complete').setup()")
  end
end

return M
