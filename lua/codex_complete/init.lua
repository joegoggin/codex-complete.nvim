local M = {}

local context = require("codex_complete.context")
local config_module = require("codex_complete.config")
local Engine = require("codex_complete.engine")
local ui = require("codex_complete.ui")

local state = {
  configured = false,
  enabled = false,
  config = nil,
  engine = nil,
  timer = nil,
  schedule_generation = 0,
  mappings = {},
  cache = {},
  accepted_changedtick = {},
}

local function notify(message, level)
  if state.config and state.config.notify then
    vim.notify(message, level or vim.log.levels.INFO, { title = "codex-complete.nvim" })
  end
end

local function stop_timer()
  state.schedule_generation = state.schedule_generation + 1
  if state.timer then
    state.timer:stop()
  end
end

local function cancel_work()
  stop_timer()
  if state.engine then
    state.engine:cancel()
  end
end

local function current_mode_allows_manual()
  local mode = vim.api.nvim_get_mode().mode
  return mode:sub(1, 1) == "i" or mode:sub(1, 1) == "n"
end

function M.trigger(options)
  options = options or {}
  if not state.configured then
    notify("Call require('codex_complete').setup() before requesting completions", vim.log.levels.ERROR)
    return false
  end
  if not state.enabled then
    if options.silent ~= true then
      notify("Codex completions are disabled", vim.log.levels.WARN)
    end
    return false
  end
  local manual = options.manual ~= false
  if manual and not current_mode_allows_manual() then
    return false
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local eligible, reason = context.eligible(bufnr, state.config, manual)
  if not eligible then
    if manual and options.silent ~= true then
      notify("Completion unavailable: " .. reason, vim.log.levels.WARN)
    end
    return false
  end

  cancel_work()
  ui.dismiss()
  local captured = context.capture(bufnr, vim.api.nvim_get_current_win(), state.config)
  if state.config.loading_indicator then
    ui.show_loading(captured)
  end
  state.engine:request(captured, manual)
  return true
end

function M.accept()
  local visible = ui.current()
  local accepted = ui.accept()
  if accepted and visible then
    local bufnr = visible.context.bufnr
    state.cache[bufnr] = nil
    state.accepted_changedtick[bufnr] = vim.api.nvim_buf_get_changedtick(bufnr)
  end
  return accepted
end

function M.dismiss()
  state.cache[vim.api.nvim_get_current_buf()] = nil
  ui.dismiss()
  return true
end

function M.enable()
  if not state.configured then
    return false
  end
  state.enabled = true
  return true
end

function M.disable()
  if not state.configured then
    return false
  end
  state.enabled = false
  cancel_work()
  ui.dismiss()
  return true
end

function M.toggle()
  if state.enabled then
    M.disable()
  else
    M.enable()
  end
  return state.enabled
end

function M.status()
  return {
    configured = state.configured,
    enabled = state.enabled,
    auto_trigger = state.config and state.config.auto_trigger or false,
    loading = ui.loading() ~= nil,
    suggestion_visible = ui.current() ~= nil,
    engine = state.engine and state.engine:status() or nil,
  }
end

local function schedule_auto(args)
  local bufnr = args and args.buf or vim.api.nvim_get_current_buf()
  local accepted_changedtick = state.accepted_changedtick[bufnr]
  if accepted_changedtick then
    local event = args and args.event
    if event == "CursorMovedI" or vim.api.nvim_buf_get_changedtick(bufnr) == accepted_changedtick then
      return
    end
    state.accepted_changedtick[bufnr] = nil
  end
  ui.dismiss()
  cancel_work()
  if not state.enabled or not state.config.auto_trigger then
    return
  end
  if not context.eligible(bufnr, state.config, false) then
    return
  end
  local captured = context.capture(bufnr, vim.api.nvim_get_current_win(), state.config)
  local cached = state.cache[bufnr]
  if cached then
    local remainder, paired_delimiter = context.cached_remainder(cached.context, captured, cached.completion)
    if remainder == "" then
      return
    elseif remainder then
      ui.show(captured, remainder, {
        paired_delimiter = paired_delimiter,
        highlights = state.config.highlights,
      })
      return
    end
  end

  state.schedule_generation = state.schedule_generation + 1
  local generation = state.schedule_generation
  state.timer:start(
    state.config.debounce_ms,
    0,
    vim.schedule_wrap(function()
      if generation ~= state.schedule_generation then
        return
      end
      if vim.api.nvim_get_mode().mode:sub(1, 1) ~= "i" then
        return
      end
      M.trigger({ manual = false, silent = true })
    end)
  )
end

local function clear_runtime()
  pcall(vim.api.nvim_del_augroup_by_name, "CodexComplete")
  for _, mapping in ipairs(state.mappings) do
    pcall(vim.keymap.del, mapping.mode, mapping.lhs)
  end
  state.mappings = {}
  if state.timer then
    state.timer:stop()
    state.timer:close()
    state.timer = nil
  end
  if state.engine then
    state.engine:stop()
    state.engine = nil
  end
  state.cache = {}
  state.accepted_changedtick = {}
  ui.dismiss()
end

local function set_mapping(mode, lhs, callback, description)
  if lhs == false then
    return
  end
  vim.keymap.set(mode, lhs, callback, { silent = true, desc = description })
  state.mappings[#state.mappings + 1] = { mode = mode, lhs = lhs }
end

local function create_commands()
  local commands = {
    CodexComplete = function()
      M.trigger({ manual = true })
    end,
    CodexCompleteEnable = M.enable,
    CodexCompleteDisable = M.disable,
    CodexCompleteToggle = M.toggle,
    CodexCompleteDismiss = M.dismiss,
  }
  for name, callback in pairs(commands) do
    pcall(vim.api.nvim_del_user_command, name)
    vim.api.nvim_create_user_command(name, callback, {})
  end
end

function M.setup(options)
  if state.configured then
    clear_runtime()
  end
  state.config = config_module.resolve(options)
  state.enabled = state.config.enabled
  state.timer = vim.uv.new_timer()
  state.engine = Engine.new(state.config, {
    on_finished = function(captured)
      ui.dismiss(captured.bufnr)
    end,
    on_completion = function(captured, completion)
      local reconciled, paired_delimiter = context.reconcile_completion(captured, completion)
      if reconciled == "" then
        return
      end
      state.cache[captured.bufnr] = { context = captured, completion = reconciled }
      ui.show(captured, reconciled, {
        paired_delimiter = paired_delimiter,
        highlights = state.config.highlights,
      })
    end,
    on_error = function(message)
      notify(message, vim.log.levels.ERROR)
    end,
  })
  state.configured = true

  create_commands()
  local group = vim.api.nvim_create_augroup("CodexComplete", { clear = true })
  ui.setup_highlights()
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = ui.setup_highlights,
  })
  vim.api.nvim_create_autocmd({ "TextChangedI", "TextChangedP", "CursorMovedI" }, {
    group = group,
    callback = schedule_auto,
  })
  vim.api.nvim_create_autocmd({ "InsertLeave", "BufLeave", "BufDelete", "TextChanged" }, {
    group = group,
    callback = function(args)
      cancel_work()
      ui.dismiss()
      if args.event == "BufDelete" then
        state.cache[args.buf] = nil
        state.accepted_changedtick[args.buf] = nil
      end
    end,
  })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      if state.engine then
        state.engine:stop()
      end
    end,
  })

  set_mapping("i", state.config.keymaps.accept, function()
    if not M.accept() then
      local keys = vim.api.nvim_replace_termcodes(state.config.keymaps.accept, true, false, true)
      vim.api.nvim_feedkeys(keys, "n", false)
    end
  end, "Accept Codex completion")
  set_mapping("i", state.config.keymaps.trigger, function()
    M.trigger({ manual = true })
  end, "Request Codex completion")
  set_mapping("i", state.config.keymaps.dismiss, M.dismiss, "Dismiss Codex completion")
  return M
end

M._state = state

return M
