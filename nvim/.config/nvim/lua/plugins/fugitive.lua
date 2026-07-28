return {
  "tpope/vim-fugitive",
  dependencies = { "tpope/vim-rhubarb" },
  config = function()
    vim.keymap.set("n", "<leader>g", ":Ggrep \\b", { desc = "Git grep with word boundary" })
    vim.keymap.set("n", "<leader>G", ":Ggrep <C-R><C-W><CR>", { desc = "Git grep word under cursor" })
  end,
}
