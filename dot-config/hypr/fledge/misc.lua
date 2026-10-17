-- Everything else. The input values here are only the baseline: the
-- generated ~/.local/state/fledge/hypr/input.lua (fledge settings) loads after this
-- and sets the keyboard, repeat, sensitivity and touchpad.
hl.config({
  -- https://wiki.hypr.land/Configuring/Basics/Variables/#input
  input = {
    kb_layout = "us",
    kb_variant = "",
    kb_model = "",
    kb_options = "compose:caps",
    kb_rules = "",

    follow_mouse = 1,

    sensitivity = 0, -- -1.0 - 1.0, 0 means no modification.

    touchpad = {
      natural_scroll = false,
    },
  },

  misc = {
    key_press_enables_dpms = true, -- key press will trigger wake
    mouse_move_enables_dpms = true, -- mouse move will trigger wake

    -- A restarted fledge shell may take over the existing session lock (otherwise
    -- Hyprland stays locked with "lockscreen died" and no way back in).
    allow_session_lock_restore = true,

    -- No reload on file changes: a write caught half-way (a git pull, a
    -- restow) put Hyprland in emergency mode, and once it deadlocked drawing
    -- the error bar. What writes config reloads explicitly (fledge settings
    -- apply, the toggles, bootstrap, vm.sh sync); after a hand edit, run
    -- `hyprctl reload`.
    disable_autoreload = true,
  },

  xwayland = {
    force_zero_scaling = true,
  },

  -- Don't show update on first launch
  ecosystem = {
    no_update_news = true,
  },
})
