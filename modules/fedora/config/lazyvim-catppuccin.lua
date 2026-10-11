return {
  -- Catppuccin Mocha — same palette as the kitty theme in config/kitty.conf.
  {
    "catppuccin/nvim",
    name = "catppuccin",
    priority = 1000,
    opts = {
      flavour = "mocha",
      background = { light = "latte", dark = "mocha" },
    },
  },
  -- LazyVim applies its own colorscheme (default: tokyonight) after plugins
  -- load, so a vim.cmd.colorscheme() call inside the plugin config above gets
  -- overridden. Setting LazyVim's opts.colorscheme is what actually sticks.
  {
    "LazyVim/LazyVim",
    opts = { colorscheme = "catppuccin-mocha" },
  },
}
