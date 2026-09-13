local M = {}

M.developer_instructions = table.concat({
  "You are an inline code completion and comment-to-code engine.",
  "Never call tools, inspect files, run commands, or ask questions.",
  "Use only the JSON context in the user message.",
  "Return a JSON object with one field named completion.",
  "For kind completion, the completion must contain only the exact text to insert at the cursor.",
  "For kind comment, treat instruction as a request and return only the exact code that replaces that comment.",
  "Never include comment delimiters from the instruction in a comment replacement.",
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
  local payload = {
    kind = context.kind or "completion",
    filename = context.filename,
    filetype = context.filetype,
    cursor = { line = context.row, byte_column = context.col },
    prefix = context.prefix,
    suffix = context.suffix,
  }
  if context.kind == "comment" then
    payload.instruction = context.instruction
    payload.replacement = {
      start = { line = context.edit.start_row + 1, byte_column = context.edit.start_col },
      finish = { line = context.edit.end_row + 1, byte_column = context.edit.end_col },
    }
  end
  return vim.json.encode(payload)
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
