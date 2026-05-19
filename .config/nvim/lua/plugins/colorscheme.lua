return {
  {
    "folke/tokyonight.nvim",
    opts = {
      style = "night",
      transparent = true,
      styles = {
        sidebars = "transparent",
        floats = "transparent",
      },
      on_highlights = function(hl, c)
        hl.StatusLine = { fg = c.fg_dark, bg = "NONE" }
        hl.StatusLineNC = { fg = c.fg_gutter, bg = "NONE" }
      end,
    },
  },
}
