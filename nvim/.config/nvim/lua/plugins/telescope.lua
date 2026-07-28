return {
  "nvim-telescope/telescope.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-lua/popup.nvim",
  },
  config = function()
    local builtin = require("telescope.builtin")
    vim.keymap.set("n", "<leader>l", builtin.git_files, { desc = "Telescope git files" })
    vim.keymap.set("n", "<leader>k", builtin.live_grep, { desc = "Telescope live grep" })
    vim.keymap.set("n", "<leader>f", builtin.grep_string, { desc = "Telescope grep string" })
    vim.keymap.set("n", "<leader>s", builtin.find_files, { desc = "Telescope find files" })
  end,
}
