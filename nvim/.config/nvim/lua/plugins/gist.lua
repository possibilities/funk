-- Simple gist commands using gh CLI
vim.api.nvim_create_user_command("GistCreate", function(opts)
  local lines
  if opts.range > 0 then
    lines = vim.api.nvim_buf_get_lines(0, opts.line1 - 1, opts.line2, false)
  else
    lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  end
  local content = table.concat(lines, "\n")
  local relpath = vim.fn.expand("%:.")
  if relpath == "" then
    relpath = "untitled.txt"
  end
  local title = relpath
  if opts.range > 0 then
    title = string.format("%s L%d-%d", relpath, opts.line1, opts.line2)
  end
  local filename = vim.fn.expand("%:t")
  if filename == "" then
    filename = "untitled.txt"
  end
  local cmd = string.format("gh gist create --web -d %s -f %s -", vim.fn.shellescape(title), vim.fn.shellescape(filename))
  local url = vim.fn.system(cmd, content)
  url = vim.trim(url)
  if vim.v.shell_error == 0 and url ~= "" then
    vim.fn.setreg("+", url)
    vim.notify("Gist created: " .. url, vim.log.levels.INFO)
  else
    vim.notify("Failed to create gist", vim.log.levels.ERROR)
  end
end, { range = true, desc = "Create gist from buffer or selection" })

vim.api.nvim_create_user_command("GistList", function()
  vim.cmd("split term://gh gist list")
end, { desc = "List gists" })

vim.keymap.set("n", "<leader>gi", "<cmd>GistCreate<cr>", { desc = "Create gist from file" })
vim.keymap.set("v", "<leader>gi", ":GistCreate<cr>", { desc = "Create gist from selection" })
vim.keymap.set("n", "<leader>gl", "<cmd>GistList<cr>", { desc = "List gists" })

return {}
