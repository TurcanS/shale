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
}
for keys, action in pairs(shortcuts) do
    hl.bind(keys, hl.dsp.exec_cmd(command .. action))
end
-- Lets hyprlock take over if the shell's lock screen stops while the session is locked.
hl.config({ misc = { allow_session_lock_restore = true } })
hl.layer_rule({ name = "shale-motion", match = { namespace = "^shale.*" }, no_anim = true })
hl.on("hyprland.start", function()
    hl.exec_cmd(command .. "start")
end)
