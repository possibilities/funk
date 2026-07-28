-- Bootstrap lazy.nvim plugin manager
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable",
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

-- Set leader key to Space
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Enable true color support
vim.opt.termguicolors = true

-- Disable mouse support
vim.opt.mouse = ""

-- Use interactive shell for ! commands (loads aliases from .zshrc)
vim.opt.shellcmdflag = "-ic"

-- Line numbers
vim.opt.number = true

-- Search settings
vim.opt.hlsearch = false
vim.opt.incsearch = true
vim.opt.ignorecase = true
vim.opt.smartcase = true

-- Auto-reload files changed outside of nvim
vim.opt.autoread = true
vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter" }, {
  command = "checktime",
})

-- Detect uv shebang as python
vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
  callback = function()
    local first_line = vim.fn.getline(1)
    if first_line:match("^#!.*uv") then
      vim.bo.filetype = "python"
    end
  end,
})

-- Buffer navigation
vim.keymap.set('n', '<Tab>', ':bn<CR>', { silent = true })
vim.keymap.set('n', '<S-Tab>', ':bp<CR>', { silent = true })
vim.keymap.set('n', 'Q', ':bd<CR>:lclose<CR>', { silent = true })

-- Save helpers
vim.keymap.set('n', '<Leader>j', ':update<CR>', { silent = true })
vim.keymap.set('n', '<Leader>a', ':update<CR>:quit<CR>', { silent = true })

-- Copy to system clipboard with Ctrl+C in visual mode
vim.keymap.set('v', '<C-c>', '"+y')

-- Copy to system clipboard with leader+y (works with motions in normal mode too)
vim.keymap.set({'n', 'v'}, '<Leader>y', '"+y')
vim.keymap.set('n', '<Leader>Y', '"+Y')

-- Load plugins from lua/plugins/
require("lazy").setup("plugins")
