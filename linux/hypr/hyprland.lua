-- Catppuccin Mocha colors (mirrored from mocha.conf which is kept for hyprlock/hypridle)
local rosewater = "rgba(f5e0dcff)"
local flamingo  = "rgba(f2cdcdff)"
local pink      = "rgba(f5c2e7ff)"
local mauve     = "rgba(cba6f7ff)"
local red       = "rgba(f38ba8ff)"
local maroon    = "rgba(eba0acff)"
local peach     = "rgba(fab387ff)"
local yellow    = "rgba(f9e2afff)"
local green     = "rgba(a6e3a1ff)"
local teal      = "rgba(94e2d5ff)"
local sky       = "rgba(89dcebff)"
local sapphire  = "rgba(74c7ecff)"
local blue      = "rgba(89b4faff)"
local lavender  = "rgba(b4befeff)"
local text      = "rgba(cdd6f4ff)"
local subtext1  = "rgba(bac2deff)"
local subtext0  = "rgba(a6adc8ff)"
local overlay2  = "rgba(9399b2ff)"
local overlay1  = "rgba(7f849cff)"
local overlay0  = "rgba(6c7086ff)"
local surface2  = "rgba(585b70ff)"
local surface1  = "rgba(45475aff)"
local surface0  = "rgba(313244ff)"
local base      = "rgba(1e1e2eff)"
local mantle    = "rgba(181825ff)"
local crust     = "rgba(11111bff)"

--------------------
---- MONITORS ----
--------------------

hl.monitor({ output = "eDP-1", mode = "2880x1920@120.0",  position = "0x0",  scale = 1.67 })
hl.monitor({ output = "DP-7",  mode = "3440x1440@165.00", position = "auto", scale = 1.25 })

--------------------
---- ENVIRONMENT ----
--------------------

hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")

--------------------
---- AUTOSTART ----
--------------------

-- DankMaterialShell (bar, notifications, launcher, clipboard, lock, idle,
-- wallpaper, night mode) is started via its systemd user service.
hl.on("hyprland.start", function()
  hl.exec_cmd("systemctl --user start hyprpolkitagent")
end)

--------------------
---- SETTINGS ----
--------------------

hl.config({
  general = {
    gaps_in = 5,
    gaps_out = 10,
    border_size = 2,
    col = {
      active_border   = { colors = { blue, lavender }, angle = 45 },
      inactive_border = surface0,
    },
    layout = "dwindle",
  },
  decoration = {
    rounding = 10,
    active_opacity     = 1.0,
    inactive_opacity   = 1.0,
    fullscreen_opacity = 1.0,
    blur = {
      enabled = true,
      size    = 8,
      passes  = 2,
    },
    shadow = {
      enabled      = true,
      range        = 15,
      render_power = 3,
      color          = crust,
      color_inactive = mantle,
      offset         = "0 0",
    },
  },
  animations = {
    enabled = true,
  },
  misc = {
    disable_hyprland_logo    = true,
    disable_splash_rendering = true,
  },
  input = {
    kb_layout  = "us,il",
    kb_variant = "",
    kb_model   = "",
    kb_options = "",
    kb_rules   = "",
    follow_mouse = 1,
    sensitivity  = 0,
    touchpad = {
      natural_scroll = true,
    },
  },
  binds = {
    drag_threshold = 10,
  },
})

hl.config({
  ecosystem = {
    no_update_news      = true,
    no_donation_nag     = true,
    enforce_permissions = true,
  },
})

--------------------
---- GESTURES ----
--------------------

hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })

--------------------
---- LAYER RULES ----
--------------------

hl.layer_rule({
  name  = "blur-logout",
  match = { namespace = "logout_dialog" },
  blur  = true,
})

--------------------
---- WINDOW RULES ----
--------------------

hl.window_rule({
  name  = "mpv-idle-inhibit",
  match = { class = "^(mpv)$" },
  idle_inhibit = "fullscreen",
})
hl.window_rule({
  name  = "zwift-idle-inhibit-class",
  match = { class = "^(zwift)$" },
  idle_inhibit = "fullscreen",
})
hl.window_rule({
  name  = "zwift-idle-inhibit-title",
  match = { title = "^(Zwift)$" },
  idle_inhibit = "fullscreen",
})
hl.window_rule({
  name  = "zwift-idle-inhibit-initial-title",
  match = { initial_title = "^(Zwift)$" },
  idle_inhibit = "fullscreen",
})

--------------------
---- PERMISSIONS ----
--------------------

hl.permission("/nix/store/.*/bin/hyprshot", "screencopy", "allow")
hl.permission("/nix/store/.*/bin/grim",     "screencopy", "allow")

--------------------
---- KEYBINDINGS ----
--------------------

local mainMod = "SUPER"
local hyper   = "SUPER + ALT + CTRL + SHIFT"

-- Resize submap
hl.define_submap("resize", function()
  hl.bind("J",        hl.dsp.exec_cmd("hyprctl dispatch resizeactive -10 0"), { repeating = true })
  hl.bind("K",        hl.dsp.exec_cmd("hyprctl dispatch resizeactive 0 10"),  { repeating = true })
  hl.bind("L",        hl.dsp.exec_cmd("hyprctl dispatch resizeactive 0 -10"), { repeating = true })
  hl.bind("SEMICOLON", hl.dsp.exec_cmd("hyprctl dispatch resizeactive 10 0"), { repeating = true })
  hl.bind("escape",   hl.dsp.submap("reset"))
end)
hl.bind(mainMod .. " + R", hl.dsp.submap("resize"))

-- Move submap
hl.define_submap("move", function()
  hl.bind("J",        hl.dsp.exec_cmd("hyprctl dispatch movewindow l"))
  hl.bind("K",        hl.dsp.exec_cmd("hyprctl dispatch movewindow d"))
  hl.bind("L",        hl.dsp.exec_cmd("hyprctl dispatch movewindow u"))
  hl.bind("SEMICOLON", hl.dsp.exec_cmd("hyprctl dispatch movewindow r"))
  hl.bind("escape",   hl.dsp.submap("reset"))
end)
hl.bind(mainMod .. " + M", hl.dsp.submap("move"))

-- Screenshot save-to-file submap
hl.define_submap("screenshot_save", function()
  hl.bind("M", function()
    hl.exec_cmd("hyprshot -m output")
    hl.dispatch(hl.dsp.submap("reset"))
  end)
  hl.bind("W", function()
    hl.exec_cmd("hyprshot -m window")
    hl.dispatch(hl.dsp.submap("reset"))
  end)
  hl.bind("R", function()
    hl.exec_cmd("hyprshot -m region")
    hl.dispatch(hl.dsp.submap("reset"))
  end)
  hl.bind("escape", hl.dsp.submap("reset"))
end)

-- Screenshot clipboard submap
hl.define_submap("screenshot", function()
  hl.bind("M", function()
    hl.exec_cmd("hyprshot -m output --clipboard-only")
    hl.dispatch(hl.dsp.submap("reset"))
  end)
  hl.bind("W", function()
    hl.exec_cmd("hyprshot -m window --clipboard-only")
    hl.dispatch(hl.dsp.submap("reset"))
  end)
  hl.bind("R", function()
    hl.exec_cmd("hyprshot -m region --clipboard-only")
    hl.dispatch(hl.dsp.submap("reset"))
  end)
  hl.bind("S",      hl.dsp.submap("screenshot_save"))
  hl.bind("escape", hl.dsp.submap("reset"))
end)
hl.bind(mainMod .. " + S", hl.dsp.submap("screenshot"))

-- Focus navigation (vim-style: j=left, k=down, l=up, ;=right)
hl.bind(mainMod .. " + J",        hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + K",        hl.dsp.focus({ direction = "down" }))
hl.bind(mainMod .. " + L",        hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + SEMICOLON", hl.dsp.focus({ direction = "right" }))

-- Workspace switching and window movement
for i = 1, 9 do
  hl.bind(mainMod .. " + " .. i,         hl.dsp.focus({ workspace = i }))
  hl.bind(mainMod .. " + SHIFT + " .. i, hl.dsp.window.move({ workspace = i }))
end
hl.bind(mainMod .. " + 0",         hl.dsp.focus({ workspace = 10 }))
hl.bind(mainMod .. " + SHIFT + 0", hl.dsp.window.move({ workspace = 10 }))

-- Mouse window management
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Audio controls
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("dms ipc call audio increment 5"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("dms ipc call audio decrement 5"), { locked = true, repeating = true })
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd("dms ipc call audio mute"),         { locked = true })

-- Brightness controls
hl.bind("XF86MonBrightnessUp",           hl.dsp.exec_cmd("dms ipc call brightness increment 5 \"\""),     { repeating = true })
hl.bind("XF86MonBrightnessDown",         hl.dsp.exec_cmd("dms ipc call brightness decrement 5 \"\""),     { repeating = true })

-- Media controls
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"),   { locked = true })
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"),       { locked = true })

-- Window management
hl.bind(mainMod .. " + O",         hl.dsp.exec_cmd("dms ipc call lock lock"))
hl.bind(mainMod .. " + Q",         hl.dsp.window.close())
hl.bind(mainMod .. " + SHIFT + F", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + F",         hl.dsp.window.fullscreen())
hl.bind(mainMod .. " + SHIFT + E", hl.dsp.exit())

-- Utilities
hl.bind(mainMod .. " + V", hl.dsp.exec_cmd("dms ipc call clipboard toggle"))
hl.bind(mainMod .. " + N", hl.dsp.exec_cmd("hyprctl switchxkblayout all next"))

-- Common apps
hl.bind(mainMod .. " + space",  hl.dsp.exec_cmd("dms ipc call spotlight toggle"))
hl.bind(mainMod .. " + return", hl.dsp.exec_cmd("kitty --title kitty"))
hl.bind(mainMod .. " + E",      hl.dsp.exec_cmd("kitty --detach yazi"))

-- Hyper key apps
hl.bind(hyper .. " + A", hl.dsp.exec_cmd("firefox"))
hl.bind(hyper .. " + S", hl.dsp.exec_cmd("anki"))
hl.bind(hyper .. " + D", hl.dsp.exec_cmd("zwift"))
hl.bind(hyper .. " + F", hl.dsp.exec_cmd("kitty --detach spotify_player"))
hl.bind(hyper .. " + M", hl.dsp.exec_cmd("kitty --detach neomutt"))
