local M = {}

local namespace = vim.api.nvim_create_namespace("codex_complete")
local suggestion
local loading
local loading_generation = 0
local loading_frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
local loading_interval_ms = 100
local default_highlights = {
  suggestion = "CodexCompleteSuggestion",
  background = "CodexCompleteSuggestionBackground",
  existing_delimiter = "MatchParen",
}

function M.setup_highlights()
  vim.api.nvim_set_hl(0, default_highlights.suggestion, { fg = "#000000", ctermfg = 0 })
  vim.api.nvim_set_hl(0, default_highlights.background, { bg = "#50A14F", ctermbg = 71 })
end

local function lines(value)
  return vim.split(value, "\n", { plain = true })
end

function M.dismiss(bufnr)
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)
  elseif suggestion and vim.api.nvim_buf_is_valid(suggestion.context.bufnr) then
    vim.api.nvim_buf_clear_namespace(suggestion.context.bufnr, namespace, 0, -1)
  elseif loading and vim.api.nvim_buf_is_valid(loading.context.bufnr) then
    vim.api.nvim_buf_clear_namespace(loading.context.bufnr, namespace, 0, -1)
  end
  if not bufnr or (suggestion and suggestion.context.bufnr == bufnr) then
    suggestion = nil
  end
  if not bufnr or (loading and loading.context.bufnr == bufnr) then
    loading = nil
    loading_generation = loading_generation + 1
  end
end

local function render_loading(generation)
  if not loading or loading.generation ~= generation then
    return
  end
  local context = require("codex_complete.context")
  if not context.is_current(loading.context) then
    M.dismiss(loading.context.bufnr)
    return
  end

  local ok, extmark_id = pcall(
    vim.api.nvim_buf_set_extmark,
    loading.context.bufnr,
    namespace,
    loading.context.row - 1,
    loading.context.col,
    {
      id = loading.extmark_id,
      virt_text = { { "  " .. loading_frames[loading.frame], "DiagnosticHint" } },
      virt_text_pos = "inline",
      hl_mode = "combine",
    }
  )
  if not ok then
    M.dismiss(loading.context.bufnr)
    return
  end
  loading.extmark_id = extmark_id
  loading.frame = loading.frame % #loading_frames + 1
  vim.defer_fn(function()
    render_loading(generation)
  end, loading_interval_ms)
end

function M.show_loading(context)
  M.dismiss()
  loading_generation = loading_generation + 1
  loading = {
    context = context,
    extmark_id = nil,
    frame = 1,
    generation = loading_generation,
  }
  render_loading(loading.generation)
end

local function suggestion_highlight(highlights)
  if highlights.background == false then
    return highlights.suggestion
  end
  return { highlights.background, highlights.suggestion }
end

local function completion_chunks(completion, highlights, paired_delimiter)
  local parts = lines(completion)
  local highlight = suggestion_highlight(highlights)
  local chunks = {}
  for index, part in ipairs(parts) do
    chunks[index] = { { part, highlight } }
  end

  if not paired_delimiter then
    return chunks
  end

  local before_closer = completion:sub(1, paired_delimiter.closer_index - 1)
  local _, newline_count = before_closer:gsub("\n", "")
  local line_index = newline_count + 1
  local line = parts[line_index]
  local line_prefix = before_closer:match("[^\n]*$") or ""
  local delimiter_start = #line_prefix + 1
  local delimiter_end = delimiter_start + paired_delimiter.replace_length - 1
  local line_chunks = {}

  if delimiter_start > 1 then
    line_chunks[#line_chunks + 1] = { line:sub(1, delimiter_start - 1), highlight }
  end
  line_chunks[#line_chunks + 1] = {
    line:sub(delimiter_start, delimiter_end),
    highlights.existing_delimiter or default_highlights.existing_delimiter,
  }
  if delimiter_end < #line then
    line_chunks[#line_chunks + 1] = { line:sub(delimiter_end + 1), highlight }
  end
  chunks[line_index] = line_chunks
  return chunks
end

local function render_completion(context, completion, col, highlights, paired_delimiter)
  if completion == "" then
    return
  end
  local chunks = completion_chunks(completion, highlights, paired_delimiter)
  local extmark_options = {
    virt_text = chunks[1],
    virt_text_pos = "inline",
    hl_mode = "replace",
  }
  if #chunks > 1 then
    extmark_options.virt_lines = {}
    for index = 2, #chunks do
      extmark_options.virt_lines[#extmark_options.virt_lines + 1] = chunks[index]
    end
  end
  vim.api.nvim_buf_set_extmark(context.bufnr, namespace, context.row - 1, col, extmark_options)
end

local function mask_existing_closer(context, replace_length)
  vim.api.nvim_buf_set_extmark(context.bufnr, namespace, context.row - 1, context.col, {
    virt_text = { { string.rep(" ", replace_length), "Normal" } },
    virt_text_pos = "overlay",
    hl_mode = "replace",
    priority = 5000,
  })
end

function M.show(context, completion, options)
  M.dismiss()
  options = options or {}
  local highlights = options.highlights or default_highlights
  local paired_delimiter = options.paired_delimiter
  if paired_delimiter then
    local closer_index = paired_delimiter.closer_index
    local before_closer = completion:sub(1, closer_index - 1)
    if before_closer:find("\n", 1, true) then
      render_completion(context, completion, context.col, highlights, paired_delimiter)
      mask_existing_closer(context, paired_delimiter.replace_length)
    else
      render_completion(context, before_closer, context.col, highlights)
      render_completion(
        context,
        completion:sub(closer_index + paired_delimiter.replace_length),
        context.col + paired_delimiter.replace_length,
        highlights
      )
    end
  else
    render_completion(context, completion, context.col, highlights)
  end
  suggestion = {
    context = context,
    completion = completion,
    replace_length = paired_delimiter and paired_delimiter.replace_length or 0,
  }
end

function M.show_replacement(context, completion, options)
  M.dismiss()
  options = options or {}
  local highlights = options.highlights or default_highlights
  local chunks = completion_chunks(completion, highlights)
  local source_line = vim.api.nvim_buf_get_lines(
    context.bufnr,
    context.edit.start_row,
    context.edit.start_row + 1,
    false
  )[1] or ""
  local prefix_width = vim.fn.strdisplaywidth(source_line:sub(1, context.edit.start_col))
  if prefix_width > 0 then
    table.insert(chunks[1], 1, { string.rep(" ", prefix_width), "Normal" })
  end
  local line_count = vim.api.nvim_buf_line_count(context.bufnr)
  local preview_row = math.min(context.edit.end_row, line_count - 1)
  vim.api.nvim_buf_set_extmark(context.bufnr, namespace, preview_row, 0, {
    virt_lines = chunks,
    virt_lines_above = false,
  })
  suggestion = {
    context = context,
    completion = completion,
    range = context.edit,
  }
end

function M.accept()
  if not suggestion then
    return false
  end
  local current = suggestion
  local context = require("codex_complete.context")
  if not context.is_current(current.context) then
    M.dismiss()
    return false
  end

  local parts = lines(current.completion)
  M.dismiss()
  local range = current.range
    or {
      start_row = current.context.row - 1,
      start_col = current.context.col,
      end_row = current.context.row - 1,
      end_col = current.context.col + current.replace_length,
    }
  vim.api.nvim_buf_set_text(
    current.context.bufnr,
    range.start_row,
    range.start_col,
    range.end_row,
    range.end_col,
    parts
  )
  if vim.api.nvim_win_is_valid(current.context.winid) then
    local target_col = #parts == 1 and range.start_col + #parts[1] or #parts[#parts]
    vim.api.nvim_win_set_cursor(current.context.winid, {
      range.start_row + #parts,
      target_col,
    })
  end
  return true
end

function M.current()
  return suggestion
end

function M.loading()
  return loading
end

return M
