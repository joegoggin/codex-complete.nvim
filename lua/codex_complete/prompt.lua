local M = {}

M.developer_instructions = table.concat({
  "You are an inline code completion engine.",
  "Never call tools, inspect files, run commands, or ask questions.",
  "Use only the JSON context in the user message.",
  "Return a JSON object with one field named completion.",
  "The completion must contain only the exact text to insert at the cursor.",
  "Do not repeat the prefix or suffix, and do not use Markdown fences.",
  "Prefer a concise, idiomatic continuation. Return an empty string when no useful completion is clear.",
}, " ")

M.output_schema = {
  type = "object",
  properties = {
    completion = { type = "string" },
  },
  required = { "completion" },
  additionalProperties = false,
}

function M.build(context)
  return vim.json.encode({
    filename = context.filename,
    filetype = context.filetype,
    cursor = { line = context.row, byte_column = context.col },
    prefix = context.prefix,
    suffix = context.suffix,
  })
end

local function remove_fence(value)
  local language, body = value:match("^```([^\n]*)\n(.*)\n```%s*$")
  if language ~= nil then
    return body
  end
  return value
end

function M.parse(message, config)
  if type(message) ~= "string" or message == "" then
    return nil, "Codex returned no completion"
  end

  local ok, decoded = pcall(vim.json.decode, message)
  if not ok or type(decoded) ~= "table" or type(decoded.completion) ~= "string" then
    return nil, "Codex returned malformed structured output"
  end

  local completion = remove_fence(decoded.completion:gsub("\r\n", "\n"):gsub("\r", "\n"))
  if completion:find("%z") then
    return nil, "Codex returned an invalid NUL byte"
  end
  if completion == "" then
    return nil, "Codex did not suggest a completion"
  end
  if #completion > config.suggestion.max_bytes then
    return nil, "Codex completion exceeded the configured byte limit"
  end
  local lines = vim.split(completion, "\n", { plain = true })
  if #lines > config.suggestion.max_lines then
    return nil, "Codex completion exceeded the configured line limit"
  end
  return completion
end

return M
