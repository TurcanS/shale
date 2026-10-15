-- Shale wallpaper picker. This file owns only the requested shortcut; once it is changed in Settings, shale.lua binds it.
local config = os.getenv("XDG_CONFIG_HOME")
local chunk = loadfile(((config and config ~= "") and config or os.getenv("HOME") .. "/.config") .. "/shale/shortcuts.lua")
local ok, changed = pcall(chunk or function() return {} end)
if not ok or type(changed) ~= "table" or changed.wallpaper == nil then
    hl.bind("SUPER + SHIFT + W", hl.dsp.exec_cmd(os.getenv("HOME") .. "/.local/bin/shale wallpaper"), { description = "Shale: wallpaper" })
end
