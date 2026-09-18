-- variables.lua
-- Shared values. Required by binds.lua (and anything else that needs them).

local M = {}

M.mainMod = "SUPER"

-- Noctalia IPC prefix.
--   v4 (Quickshell):  "qs -c noctalia-shell ipc call"
--   v5 (native):      "noctalia msg"
M.ipc = "noctalia msg"

M.home = os.getenv("HOME")

return M
