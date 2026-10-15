return {
  {
    "rebelot/kanagawa.nvim",
    opts = {
      transparent = true,
      background = { dark = "wave", light = "lotus" },
      colors = {
        theme = {
          all = {
            ui = { bg_gutter = "none" }, -- no solid strip behind line numbers/signs
          },
        },
      },
    },
  },

  {
    "LazyVim/LazyVim",
    opts = { colorscheme = "kanagawa" },
  },
}