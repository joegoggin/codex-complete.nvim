return function()
  local status = require("codex_complete").status()
  if not status.configured then
    return ""
  end

  local enabled = status.enabled and "enabled" or "disabled"
  local model = status.model.current or "Codex default"
  return ("Status: %s | Model: %s | Effort: %s"):format(enabled, model, status.effort.current)
end
