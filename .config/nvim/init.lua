-- bootstrap lazy.nvim, LazyVim and your plugins
require("config.lazy")

-- Add this after the LazyVim setup
if vim.fn.has('wsl') == 0 and os.getenv('WAYLAND_DISPLAY') then
  vim.g.clipboard = {
    name = 'wl-clipboard',
    copy = {
      ['+'] = 'wl-copy',
      ['*'] = 'wl-copy',
    },
    paste = {
      ['+'] = 'wl-paste',
      ['*'] = 'wl-paste',
    },
    cache_enabled = 1,
  }
end
