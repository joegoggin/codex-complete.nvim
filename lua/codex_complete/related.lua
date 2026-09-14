--- Bounded cross-file context retrieval for inline suggestions.
---
--- Combines language-server definitions with project searches and live buffers.

local M = {}
local cache = {}
local keywords = {
  ["let"] = true,
  ["const"] = true,
  ["mut"] = true,
  ["pub"] = true,
  ["return"] = true,
  ["function"] = true,
  ["local"] = true,
  ["struct"] = true,
  ["class"] = true,
  ["self"] = true,
}

--- Resolves a canonical file path.
---
---@param path string
---@return string path
---
local function canonical(path)
  return vim.fs.normalize(vim.uv.fs_realpath(path) or path)
end

--- Checks whether a path belongs to a project.
---
---@param path string
---@param root string
---@return boolean inside
---
local function inside(path, root)
  return path == root or path:sub(1, #root + 1) == root .. "/"
end

--- Finds the nearest applicable language-server workspace or Git root.
---
---@param captured table
---@return string root
---@return string cwd
---
function M.project(captured)
  local cwd = captured.filename ~= "" and vim.fs.dirname(captured.filename) or vim.fn.getcwd()
  cwd = canonical(cwd)
  local roots = {}
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = captured.bufnr })) do
    for _, workspace in ipairs(client.workspace_folders or {}) do
      local root = canonical(vim.uri_to_fname(workspace.uri))
      if inside(cwd, root) then
        roots[#roots + 1] = root
      end
    end
    local root = client.config and client.config.root_dir
    if type(root) == "string" and inside(cwd, canonical(root)) then
      roots[#roots + 1] = canonical(root)
    end
  end
  table.sort(roots, function(a, b)
    return #a > #b
  end)
  local git = vim.fs.find(".git", { path = cwd, upward = true })[1]
  return roots[1] or (git and vim.fs.dirname(git)) or cwd, cwd
end

--- Captures a source revision without retaining its contents.
---
---@param path string
---@return string revision
---
local function revision(path)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and canonical(vim.api.nvim_buf_get_name(buf)) == path then
      return "buffer:" .. buf .. ":" .. vim.api.nvim_buf_get_changedtick(buf)
    end
  end
  local stat = vim.uv.fs_stat(path)
  return stat and table.concat({ stat.size, stat.mtime.sec, stat.mtime.nsec }, ":") or "missing"
end

--- Checks whether every included source still has the captured revision.
---
---@param captured table
---@return boolean valid
---
function M.valid(captured)
  for path, version in pairs(captured.dependencies or {}) do
    if revision(path) ~= version then
      return false
    end
  end
  return true
end

--- Collects bounded context and returns a cancellation callback.
---
---@param captured table
---@param config table
---@param callback fun()
---@return function cancel
---
function M.collect(captured, config, callback)
  local root, cwd = M.project(captured)
  captured.cwd = cwd
  captured.related = {}
  captured.dependencies = {}
  local options = config.context.related
  local started = vim.uv.hrtime()
  local done, bytes = false, 0
  local timer, process
  local requests, seen = {}, {}
  local pending, search_done = 0, false
  local hits = 0
  local output = ""
  local fallback = {}
  local add
  local candidates = {}
  local first = math.max(0, captured.row - 12)
  local lines = vim.api.nvim_buf_get_lines(captured.bufnr, first, captured.row, false)
  local symbols = {}
  for index = #lines, 1, -1 do
    local offset = 1
    while #candidates < 8 do
      local begin, finish, name = lines[index]:find("([%a_][%w_]*)", offset)
      if not begin then
        break
      end
      if #name > 2 and not symbols[name] and not keywords[name] then
        symbols[name] = true
        candidates[#candidates + 1] = { name = name, row = first + index - 1, col = begin - 1 }
      end
      offset = finish + 1
    end
  end
  local key_names = {}
  for _, candidate in ipairs(candidates) do
    key_names[#key_names + 1] = candidate.name
  end
  local key = root
    .. "\0"
    .. captured.filename
    .. "\0"
    .. table.concat(key_names, ",")
    .. ":"
    .. options.max_bytes
    .. ":"
    .. options.max_snippets
    .. ":"
    .. table.concat(config.sensitive_patterns, ",")
    .. ":"
    .. first

  --- Ranks declarations and nearby identifiers above generic matches.
  ---
  ---@param path string
  ---@param row integer
  ---@param line string
  ---
  local function enqueue(path, row, line)
    local score = 0
    local extension = captured.filename:match("%.[^./]+$")
    if extension and path:sub(-#extension) == extension then
      score = score + 100
    end
    for index, candidate in ipairs(candidates) do
      if line:find("%f[%w_]" .. candidate.name .. "%f[^%w_]") then
        score = score + (9 - index) * 10
        for _, keyword in ipairs({ "struct", "class", "interface", "type", "function", "fn", "def" }) do
          if line:match("^%s*[%w_%s]*" .. keyword .. "%s+" .. candidate.name .. "%f[^%w_]") then
            score = score + 200
          end
        end
      end
    end
    fallback[#fallback + 1] = { path = path, row = row, score = score }
    if #fallback > 256 then
      table.sort(fallback, function(a, b)
        return (a.score or 0) > (b.score or 0)
      end)
      fallback[#fallback] = nil
    end
  end

  --- Stops outstanding retrieval work.
  ---
  local function cancel()
    done = true
    if timer then
      timer:stop()
      timer:close()
      timer = nil
    end
    if process then
      pcall(process.kill, process, 15)
      process = nil
    end
    for _, request in ipairs(requests) do
      request.client.cancel_request(request.id)
    end
  end

  --- Publishes metadata and completes exactly once.
  ---
  local function finish()
    if done then
      return
    end
    for line in output:gmatch("[^\n]+\n") do
      local ok, event = pcall(vim.json.decode, line)
      if ok and event.type == "match" and event.data.path.text then
        enqueue(event.data.path.text, event.data.line_number - 1, event.data.lines.text or "")
      end
    end
    output = ""
    table.sort(fallback, function(a, b)
      if (a.score or 0) ~= (b.score or 0) then
        return (a.score or 0) > (b.score or 0)
      end
      return a.path == b.path and a.row < b.row or a.path < b.path
    end)
    local minimum_score = math.max(0, ((fallback[1] or {}).score or 0) - 120)
    for _, candidate in ipairs(fallback) do
      if candidate.score == nil or candidate.score >= minimum_score then
        add(candidate.path, candidate.row)
      end
    end
    cancel()
    captured.retrieval = { duration_ms = (vim.uv.hrtime() - started) / 1e6, cache_hits = hits, sources = {} }
    for _, snippet in ipairs(captured.related) do
      captured.retrieval.sources[#captured.retrieval.sources + 1] = snippet.filename
    end
    if #captured.related > 0 then
      if vim.tbl_count(cache) >= 64 then
        cache = {}
      end
      cache[key] = { related = vim.deepcopy(captured.related), dependencies = vim.deepcopy(captured.dependencies) }
    end
    callback()
  end

  --- Adds a bounded snippet, preferring unsaved buffer text.
  ---
  ---@param filename string
  ---@param row integer
  ---@param end_row integer|nil
  ---
  add = function(filename, row, end_row)
    if done or #captured.related >= options.max_snippets then
      return
    end
    local path = canonical(filename)
    if not inside(path, root) then
      return
    end
    for part in path:sub(#root + 2):gmatch("[^/]+") do
      if part == "target" or part == "node_modules" or part == "dist" or part == "build" or part == "vendor" then
        return
      end
    end
    if path == canonical(captured.filename) and row >= first and row < captured.row + config.context.after_lines then
      return
    end
    for _, pattern in ipairs(config.sensitive_patterns) do
      if vim.fs.basename(path):lower():find(pattern) then
        return
      end
    end
    local start = math.max(0, row - 3)
    local stop = math.min(start + 100, math.max(row + 45, end_row or row))
    local id = path .. ":" .. row
    if seen[id] then
      return
    end
    for _, snippet in ipairs(captured.related) do
      if snippet.filename == path and row + 1 >= snippet.start_line and row + 1 <= snippet.end_line then
        return
      end
    end
    local source
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(buf) and canonical(vim.api.nvim_buf_get_name(buf)) == path then
        local count = vim.api.nvim_buf_line_count(buf)
        if start >= count then
          return
        end
        source = vim.api.nvim_buf_get_lines(buf, start, math.min(stop, count), false)
        break
      end
    end
    if not source then
      local stat = vim.uv.fs_stat(path)
      if not stat or stat.type ~= "file" or stat.size > 256 * 1024 then
        return
      end
      local ok, content = pcall(vim.fn.readfile, path, "", stop)
      if not ok then
        return
      end
      source = vim.list_slice(content, start + 1, stop)
    end
    local selected = {}
    for _, line in ipairs(source) do
      if line:find("%z") or bytes + #line + 1 > options.max_bytes then
        break
      end
      selected[#selected + 1] = line
      bytes = bytes + #line + 1
    end
    if #selected == 0 then
      return
    end
    seen[id] = true
    captured.dependencies[path] = revision(path)
    captured.related[#captured.related + 1] = {
      filename = path,
      start_line = start + 1,
      end_line = start + #selected,
      text = table.concat(selected, "\n"),
    }
  end

  if not options.enabled then
    finish()
    return cancel
  end
  local cached = cache[key]
  if cached and M.valid(cached) then
    captured.related = vim.deepcopy(cached.related)
    captured.dependencies = vim.deepcopy(cached.dependencies)
    hits = #captured.related
    finish()
    return cancel
  end
  timer = vim.uv.new_timer()
  timer:start(options.timeout_ms, 0, vim.schedule_wrap(finish))
  if captured.row > config.context.before_lines + 40 and captured.filename ~= "" then
    fallback[#fallback + 1] = { path = captured.filename, row = 0 }
  end
  local parsed, node =
    pcall(vim.treesitter.get_node, { bufnr = captured.bufnr, pos = { captured.row - 1, captured.col } })
  if parsed then
    while node do
      if node:type():find("function") or node:type():find("method") or node:type():find("declaration") then
        local row = node:range()
        if row < first then
          fallback[#fallback + 1] = { path = captured.filename, row = row }
          break
        end
      end
      node = node:parent()
    end
  end
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = captured.bufnr })) do
    if client.supports_method("textDocument/definition") then
      for _, candidate in ipairs(candidates) do
        local line = lines[candidate.row - first + 1]
        local character = candidate.col
        if client.offset_encoding ~= "utf-8" then
          local utf32, utf16 = vim.str_utfindex(line, candidate.col)
          character = client.offset_encoding == "utf-32" and utf32 or utf16
        end
        pending = pending + 1
        local ok, id = client.request("textDocument/definition", {
          textDocument = { uri = vim.uri_from_bufnr(captured.bufnr) },
          position = { line = candidate.row, character = character },
        }, function(err, result)
          pending = pending - 1
          if done then
            return
          end
          local locations = not err
              and type(result) == "table"
              and ((result.uri or result.targetUri) and { result } or result)
            or {}
          for _, location in ipairs(locations) do
            local uri = location.uri or location.targetUri
            local range = location.targetRange or location.range
            if uri and uri:sub(1, 7) == "file://" and range then
              add(vim.uri_to_fname(uri), range.start.line, range["end"].line)
            end
          end
          if search_done and pending == 0 then
            finish()
          end
        end, captured.bufnr)
        if ok then
          requests[#requests + 1] = { client = client, id = id }
        else
          pending = pending - 1
        end
      end
    end
  end
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    local path = vim.api.nvim_buf_get_name(buf)
    if vim.api.nvim_buf_is_loaded(buf) and path ~= "" and inside(canonical(path), root) then
      local count = math.min(vim.api.nvim_buf_line_count(buf), 2000)
      for row, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, count, false)) do
        for name in pairs(symbols) do
          if line:find("%f[%w_]" .. name .. "%f[^%w_]") and line:find("[={(:]") then
            enqueue(path, row - 1, line)
            break
          end
        end
        if (vim.uv.hrtime() - started) / 1e6 >= options.timeout_ms then
          break
        end
      end
    end
  end
  if #candidates > 0 and vim.fn.executable("rg") == 1 then
    local argv = {
      "rg",
      "--json",
      "--max-count",
      "2",
      "--max-filesize",
      "256K",
      "--glob",
      "!{target,node_modules,dist,build,vendor}/**",
      "-w",
      "-F",
    }
    for _, candidate in ipairs(candidates) do
      vim.list_extend(argv, { "-e", candidate.name })
    end
    vim.list_extend(argv, { "--", root })
    process = vim.system(argv, {
      stdout = function(_, chunk)
        if not chunk or done then
          return
        end
        if #output + #chunk > 128 * 1024 then
          vim.schedule(finish)
          return
        end
        output = output .. chunk
      end,
    }, function()
      vim.schedule(function()
        if done then
          return
        end
        search_done = true
        if pending == 0 then
          finish()
        end
      end)
    end)
  else
    search_done = true
    if pending == 0 then
      finish()
    end
  end
  return cancel
end

return M
