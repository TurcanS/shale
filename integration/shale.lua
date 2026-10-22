-- Installed by Shale. Existing wallpaper, polkit and clipboard services remain owned by your config.
local command = os.getenv("HOME") .. "/.local/bin/shale "
local shortcuts = {
    ["SUPER + SPACE"] = "launcher", ["SUPER + V"] = "clipboard",
    ["SUPER + A"] = "control", ["SUPER + N"] = "notifications",
    ["SUPER + O"] = "overview", ["SUPER + COMMA"] = "settings",
    ["SUPER + SHIFT + A"] = "activity", ["CTRL + SHIFT + Escape"] = "system",
    ["SUPER + M"] = "power", ["Print"] = "screenshot region",
    ["SUPER + L"] = "lock",
    ["SHIFT + Print"] = "screenshot output", ["SUPER + Print"] = "capture",
    ["SUPER + SHIFT + D"] = "day", ["SUPER + SHIFT + N"] = "order", ["SUPER + SHIFT + L"] = "logbook",
}
-- Shortcuts changed in Settings: {action = "KEYS"} binds other keys, {action = false} none.
local config = os.getenv("XDG_CONFIG_HOME")
local custom = ((config and config ~= "") and config or os.getenv("HOME") .. "/.config") .. "/shale/shortcuts.lua"
local chunk = loadfile(custom)
local ok, changed = pcall(chunk or function() return {} end)
if not ok or type(changed) ~= "table" then changed = {} end
local function bind(keys, action)
    -- One bad entry must not cost the other shortcuts.
    pcall(hl.bind, keys, hl.dsp.exec_cmd(command .. action), { description = "Shale: " .. action })
end
for keys, action in pairs(shortcuts) do
    if changed[action] == nil then bind(keys, action) end
end
for action, keys in pairs(changed) do
    if type(action) == "string" and action:match("^[%w ]+$") and type(keys) == "string" then bind(keys, action) end
end
-- Settings records a new shortcut in this empty submap, so keys that are already bound reach it instead of acting.
-- Escape always leaves, and Settings still sees it to cancel.
hl.define_submap("shale-record", function()
    hl.bind("Escape", hl.dsp.submap("reset"), { non_consuming = true })
end)
-- Lets hyprlock take over if the shell's lock screen stops while the session is locked.
hl.config({ misc = { allow_session_lock_restore = true } })
hl.layer_rule({ name = "shale-motion", match = { namespace = "^shale.*" }, no_anim = true })
hl.on("hyprland.start", function()
    hl.exec_cmd(command .. "start")
end)
