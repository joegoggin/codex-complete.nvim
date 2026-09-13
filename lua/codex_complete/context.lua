local M = {}

local function contains(values, target)
  for _, value in ipairs(values or {}) do
    if value == target then
      return true
    end
  end
  return false
end

local function utf8_tail(value, limit)
  if #value <= limit then
    return value
  end
  local first = #value - limit + 1
  while first <= #value do
    local byte = value:byte(first)
    if byte < 128 or byte >= 192 then
      break
    end
    first = first + 1
  end
  return value:sub(first)
end

local function utf8_head(value, limit)
  if #value <= limit then
    return value
  end
  local last = limit
  while last > 0 and last < #value do
    local next_byte = value:byte(last + 1)
    if next_byte < 128 or next_byte >= 192 then
      break
    end
    last = last - 1
  end
  return value:sub(1, last)
end

local function is_sensitive(name, patterns)
  local basename = vim.fs.basename(name):lower()
  for _, pattern in ipairs(patterns or {}) do
    if basename:find(pattern) then
      return true
    end
  end
  return false
end

function M.eligible(bufnr, config, manual)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return false, "invalid buffer"
  end
  if not vim.bo[bufnr].modifiable or vim.bo[bufnr].readonly then
    return false, "buffer is not editable"
  end
  if vim.bo[bufnr].buftype ~= "" then
    return false, "special buffer"
  end

  local name = vim.api.nvim_buf_get_name(bufnr)
  if name ~= "" and is_sensitive(name, config.sensitive_patterns) then
    return false, "sensitive filename"
  end

  local filetype = vim.bo[bufnr].filetype
  if contains(config.filetypes.deny, filetype) then
    return false, "disabled filetype"
  end
  if not manual and not contains(config.filetypes.allow, filetype) then
    return false, "filetype is not enabled for automatic completion"
  end
  if config.is_eligible then
    local ok, result = pcall(config.is_eligible, bufnr, manual)
    if not ok then
      return false, "is_eligible callback failed"
    end
    if not result then
      return false, "rejected by is_eligible"
    end
  end
  return true
end

function M.capture(bufnr, winid, config)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  winid = winid or vim.api.nvim_get_current_win()
  local cursor = vim.api.nvim_win_get_cursor(winid)
  local row, col = cursor[1], cursor[2]
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local before_start = math.max(0, row - 1 - config.context.before_lines)
  local before = vim.api.nvim_buf_get_lines(bufnr, before_start, row, false)
  local current = before[#before] or ""
  before[#before] = current:sub(1, col)

  local after_end = math.min(line_count, row + config.context.after_lines)
  local after = { current:sub(col + 1) }
  vim.list_extend(after, vim.api.nvim_buf_get_lines(bufnr, row, after_end, false))

  local prefix = table.concat(before, "\n")
  local suffix = table.concat(after, "\n")
  local suffix_budget = math.floor(config.context.max_bytes / 3)
  suffix = utf8_head(suffix, suffix_budget)
  prefix = utf8_tail(prefix, config.context.max_bytes - #suffix)

  return {
    bufnr = bufnr,
    winid = winid,
    row = row,
    col = col,
    changedtick = vim.api.nvim_buf_get_changedtick(bufnr),
    filename = vim.api.nvim_buf_get_name(bufnr),
    filetype = vim.bo[bufnr].filetype,
    prefix = prefix,
    suffix = suffix,
  }
end

function M.is_current(context)
  if not context or not vim.api.nvim_buf_is_valid(context.bufnr) then
    return false
  end
  if vim.api.nvim_buf_get_changedtick(context.bufnr) ~= context.changedtick then
    return false
  end
  if not vim.api.nvim_win_is_valid(context.winid) then
    return false
  end
  local cursor = vim.api.nvim_win_get_cursor(context.winid)
  return cursor[1] == context.row and cursor[2] == context.col
end

local delimiter_pairs = {
  ["("] = ")",
  ["["] = "]",
  ["{"] = "}",
}

local function unmatched_opening(inserted, closer)
  local stack = {}
  for index = 1, #inserted do
    local character = inserted:sub(index, index)
    if delimiter_pairs[character] then
      stack[#stack + 1] = character
    elseif #stack > 0 and delimiter_pairs[stack[#stack]] == character then
      stack[#stack] = nil
    end
  end
  local opening = stack[#stack]
  if opening and delimiter_pairs[opening] == closer then
    return opening
  end
  return nil
end

local function matching_closer_index(remainder, opening, closer)
  local depth = 1
  for index = 1, #remainder do
    local character = remainder:sub(index, index)
    if character == opening then
      depth = depth + 1
    elseif character == closer then
      depth = depth - 1
      if depth == 0 then
        return index
      end
    end
  end
  return nil
end

function M.reconcile_completion(current, completion)
  local closer = current.suffix:sub(1, 1)
  local opening = unmatched_opening(current.prefix, closer)
  if not opening then
    return completion, nil
  end
  local closer_index = matching_closer_index(completion, opening, closer)
  if closer_index == nil then
    return completion, nil
  end
  local paired_delimiter = {
    closer_index = closer_index,
    replace_length = #closer,
  }
  if completion == closer then
    return "", paired_delimiter
  end
  return completion, paired_delimiter
end

function M.cached_remainder(cached, current, completion)
  if
    not cached
    or not current
    or cached.bufnr ~= current.bufnr
    or cached.filename ~= current.filename
    or cached.filetype ~= current.filetype
  then
    return nil
  end
  if current.row < cached.row or (current.row == cached.row and current.col < cached.col) then
    return nil
  end

  local ok, inserted_lines =
    pcall(vim.api.nvim_buf_get_text, current.bufnr, cached.row - 1, cached.col, current.row - 1, current.col, {})
  if not ok then
    return nil
  end
  local inserted = table.concat(inserted_lines, "\n")
  if completion:sub(1, #inserted) ~= inserted then
    return nil
  end

  local expected_prefix = cached.prefix .. inserted
  if #current.prefix > #expected_prefix then
    return nil
  end
  local current_prefix_start = #expected_prefix - #current.prefix + 1
  if current.prefix ~= expected_prefix:sub(current_prefix_start) then
    return nil
  end
  local remainder = completion:sub(#inserted + 1)
  local suffix_unchanged = cached.suffix == current.suffix
  if not suffix_unchanged and current.suffix:sub(2) ~= cached.suffix then
    return nil
  end
  local reconciled, paired_delimiter = M.reconcile_completion(current, remainder)
  if not suffix_unchanged and not paired_delimiter then
    return nil
  end
  return reconciled, paired_delimiter
end

return M
