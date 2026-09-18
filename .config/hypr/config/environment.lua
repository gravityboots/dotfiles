-- environment.lua
-- Session-wide environment variables.

---@module 'hl'

local v = require("variables")

-- Scaling
-- Pair with: gsettings set org.gnome.desktop.interface text-scaling-factor 1.2
-- Font "Adwaita Sans Regular 10px" works best for most other apps.
hl.env("QT_SCALE_FACTOR", "1.2")
-- hl.env("GDK_DPI_SCALE", "1.2")  -- mirrors the above; not needed, use nwg-look text scale 120% + font 10px

-- Paths
hl.env("HYPRSHOT_DIR", v.home .. "/Pictures/Screenshots")

-- Qt theming
hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")
hl.env("QT_QPA_PLATFORMTHEME_QT5", "qt5ct")
hl.env("QT_STYLE_OVERRIDE", "kvantum")

-- Electron / Wayland
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "wayland")
hl.env("WAYLAND_DISPLAY", "wayland-1")

-- VSCodium marketplace
hl.env("VSCODE_GALLERY_SERVICE_URL", "https://marketplace.visualstudio.com/_apis/public/gallery")
hl.env("VSCODE_GALLERY_ITEM_URL", "https://marketplace.visualstudio.com/items")
hl.env("VSCODE_GALLERY_CACHE_URL", "https://vscode.blob.core.windows.net/gallery/index")
hl.env("VSCODE_GALLERY_CONTROL_URL", "")

-- Input method (fcitx5)
hl.env("GTK_IM_MODULE", "fcitx")
hl.env("QT_IM_MODULE", "fcitx")
hl.env("XMODIFIERS", "@im=fcitx")
hl.env("SDL_IM_MODULE", "fcitx")

-- Input method (ibus) -- alternative to the fcitx block above
-- hl.env("GTK_IM_MODULE", "ibus")
-- hl.env("QT_IM_MODULE", "ibus")
-- hl.env("XMODIFIERS", "@im=ibus")

-- Fix for gpu-screen-recorder / noctalia screen recorder plugin on hybrid graphics
-- hl.env("WLR_DRM_DEVICES", "/dev/dri/card0")
