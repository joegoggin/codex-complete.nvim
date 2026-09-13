local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.cmd("filetype plugin indent off")
vim.opt.runtimepath:prepend(root)
vim.opt.runtimepath:prepend(root .. "/.deps/mini.nvim")

require("mini.test").setup({
  collect = {
    find_files = function()
      return vim.fn.globpath(root .. "/tests", "test_*.lua", false, true)
    end,
  },
})
