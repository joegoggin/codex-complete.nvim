if vim.fn.has("nvim-0.10") ~= 1 then
  vim.notify("codex-complete.nvim requires Neovim 0.10 or newer", vim.log.levels.ERROR)
end
