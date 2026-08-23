-- Omalexia: dyslexia-friendly keys and look for Omarchy.
--
-- Installed to ~/.config/hypr/omalexia.lua and loaded from hyprland.lua by
-- omalexia/install.sh. Everything here layers on top of Omarchy's defaults;
-- remove the require line (or run `omalexia off`) to switch it off.
--
-- The mental model for the keys is: F9 = talk, F10 = listen.

local home = os.getenv("HOME") or ""
local bin = home .. "/.local/bin/"
local state = (os.getenv("XDG_STATE_HOME") or (home .. "/.local/state")) .. "/omalexia"

local function read_state(name)
  local file = io.open(state .. "/" .. name, "r")
  if not file then
    return nil
  end
  local value = file:read("*l")
  file:close()
  if value and value ~= "" then
    return value
  end
  return nil
end

-- Listen ---------------------------------------------------------------------

-- F10: read the highlighted text; press again to stop.
o.bind("F10", "Read selection aloud / stop", bin .. "omalexia-say toggle")
o.bind("SHIFT + F10", "Read clipboard aloud", bin .. "omalexia-say clipboard")
o.bind("CTRL + F10", "Read screen region aloud (OCR)", bin .. "omalexia-say ocr")
o.bind("SUPER + F10", "Read faster", bin .. "omalexia-say speed up")
o.bind("SUPER + SHIFT + F10", "Read slower", bin .. "omalexia-say speed down")

-- Talk -----------------------------------------------------------------------

-- F9 (hold) and Super+Ctrl+X (toggle) come from Omarchy's own voxtype bindings.
if o.cmd_present("voxtype") then
  o.bind("SHIFT + F9", "Cancel dictation", "voxtype record cancel")
end

-- Look -----------------------------------------------------------------------

o.bind("SUPER + R", "Reading mode (narrow centred window)", bin .. "omalexia-focus toggle")
o.bind("SUPER + SHIFT + R", "Paper tint", bin .. "omalexia-tint toggle")
o.bind("SUPER + ALT + A", "Omalexia menu", "omarchy-menu toggle omalexia")

hl.config({
  decoration = {
    -- Fade the windows you are not reading so the eye lands on the right one.
    dim_inactive = true,
    dim_strength = 0.12,
  },
  misc = {
    -- Hyprland's own text (group bars, errors) in the chosen reading font.
    font_family = read_state("font") or "Atkinson Hyperlegible",
  },
  group = {
    groupbar = {
      font_family = read_state("font") or "Atkinson Hyperlegible",
      font_size = 13,
    },
  },
})

-- OCR in Dutch and English; only affects omarchy capture text and Ctrl+F10.
hl.env("OMARCHY_OCR_LANGS", "eng+nld")

-- Let Qt apps expose their text to assistive tools (Orca, AT-SPI). Cheap.
hl.env("QT_ACCESSIBILITY", "1")

-- Bigger, easier to find pointer.
hl.env("XCURSOR_SIZE", "28")
hl.env("HYPRCURSOR_SIZE", "28")

-- Optional: reduced motion. `touch ~/.local/state/omalexia/reduced-motion`.
if read_state("reduced-motion") then
  hl.config({ animations = { enabled = false } })
end
