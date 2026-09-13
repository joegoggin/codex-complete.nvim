local MiniTest = require("mini.test")
local component = require("lualine.components.codex_complete")
local plugin = require("codex_complete")

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      plugin.setup({ auto_trigger = false })
    end,
    post_case = function()
      plugin.disable()
    end,
  },
})

T["is empty before the plugin is configured"] = function()
  local configured = plugin._state.configured
  plugin._state.configured = false
  MiniTest.expect.equality(component(), "")
  plugin._state.configured = configured
end

T["shows enabled status, model, and effort"] = function()
  MiniTest.expect.equality(component(), "Status: enabled | Model: gpt-5.6-luna | Effort: low")
end

T["shows the disabled status while retaining model and effort"] = function()
  plugin.disable()
  MiniTest.expect.equality(component(), "Status: disabled | Model: gpt-5.6-luna | Effort: low")
end

T["labels an unspecified model as the Codex default"] = function()
  plugin._state.engine:set_model(nil)
  MiniTest.expect.equality(component(), "Status: enabled | Model: Codex default | Effort: low")
end

T["shows runtime model and effort selections"] = function()
  plugin._state.engine:set_model("gpt-test-pro")
  plugin._state.engine:set_effort("high")
  MiniTest.expect.equality(component(), "Status: enabled | Model: gpt-test-pro | Effort: high")
end

return T
