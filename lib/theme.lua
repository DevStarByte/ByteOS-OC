--[[
  /lib/theme.lua - ByteOS colour theme

  One 16-colour palette shared by every part of the system. Sixteen is not an
  accident: a Tier 2 GPU has exactly 16 (editable) palette slots, so keeping
  the whole OS inside this set means colours look identical on Tier 2 and
  Tier 3 instead of being snapped to whatever the default palette has nearby.

  Programs should use the role names (theme.accent, theme.err, ...) rather
  than raw hex values, so the look stays consistent and can be re-themed here.
]]--

local theme = {
  -- neutrals (dark -> light)
  bg      = 0x000000,  -- terminal background
  base    = 0x10151C,  -- desktop / large surfaces
  surface = 0x1C2430,  -- window bodies
  raised  = 0x2B3646,  -- bars, input fields, inactive buttons
  dim     = 0x4A5568,  -- borders, disabled text, ghost text
  muted   = 0x8A96A8,  -- secondary text, timestamps, hints
  fg      = 0xD8DEE9,  -- default text
  bright  = 0xFFFFFF,  -- emphasis, text on accent

  -- colours
  accent  = 0x1793D1,  -- Arch blue: titles, selection, prompt
  blue    = 0x6CB6FF,  -- directories, paths
  cyan    = 0x4FD1C5,
  green   = 0x5FD068,  -- success, executables, user prompt
  yellow  = 0xE8C061,  -- warnings, flags
  orange  = 0xF0904A,  -- numbers
  red     = 0xF0605A,  -- errors, root prompt
  magenta = 0xC792EA,  -- packages, keywords
}

-- Semantic aliases (same slots, no extra palette cost).
theme.ok   = theme.green
theme.warn = theme.yellow
theme.err  = theme.red
theme.on_accent = theme.bright  -- text drawn on an accent background

-- The 16 slots, in a fixed order, for programming the GPU palette.
theme.palette = {
  theme.bg, theme.base, theme.surface, theme.raised,
  theme.dim, theme.muted, theme.fg, theme.bright,
  theme.accent, theme.blue, theme.cyan, theme.green,
  theme.yellow, theme.orange, theme.red, theme.magenta,
}

-- Tier 1 GPUs are 1-bit: every non-zero colour is drawn white. Collapse the
-- theme to black/white by luminance so dark surfaces stay dark, and make sure
-- text on light (accent) backgrounds is black so it stays readable.
function theme.monochrome()
  local function lum(c)
    -- arithmetic instead of bit operators so this also parses on Lua 5.2
    local r, g, b = math.floor(c / 0x10000) % 256, math.floor(c / 0x100) % 256, c % 256
    return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255
  end
  for name, c in pairs(theme) do
    if type(c) == "number" then
      theme[name] = lum(c) > 0.25 and 0xFFFFFF or 0x000000
    end
  end
  theme.on_accent = 0x000000
  theme.mono = true
end

return theme
