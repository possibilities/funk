return {
  "tinted-theming/tinted-nvim",
  lazy = false,
  priority = 1000,
  config = function()
    require("tinted-colorscheme").setup(nil, {
      supports = {
        tinty = true,
        live_reload = true,
      },
    })
  end,
}
