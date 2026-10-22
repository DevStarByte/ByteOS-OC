--[[
  holo - draw on a hologram projector

    holo clear                         switch every voxel off
    holo text "HI" [COLOR]             letters, centred and as big as fit
    holo shape cube|sphere|pyramid [SIZE] [COLOR]
                                       a solid shape in the middle (SIZE in
                                       voxels, default 16, at most 32; the
                                       middle lies between two voxels, so
                                       an odd SIZE is drawn one smaller)
    holo color N 0xRRGGBB              what colour N looks like
    holo scale S                       the hologram's size (0.33 - 3)
    holo spin [SPEED]                  turn it, degrees per second (default
                                       30, 0 stops; tier 2 projectors)
    holo demo                          a little show

  The projector has 48 x 32 x 48 voxels. COLOR is 1-3 on a tier 2
  projector, which can show three colours; a tier 1 projector has one, so
  every colour is 1 there. Letters: A-Z, 0-9 and ! ? . - : (lower case is
  drawn as upper case).
]]--
local T = term.theme
local args = arg or {}
local W, H, D = 48, 32, 48

local function fail(msg) term.cwrite(T.err, "holo: "); term.write(msg .. "\n"); return 1 end

local addr = component.list("hologram")()
if not addr then return fail("no hologram projector") end
local h = component.proxy(addr)
local depth = h.maxDepth and h.maxDepth() or 1

-- Each component call takes a moment: let the machine breathe now and
-- then while drawing (OpenComputers stops a computer that never waits).
local calls = 0
local function fill(x, z, y1, y2, v)
  if y1 > y2 then return end
  h.fill(x, z, y1, y2, v)
  calls = calls + 1
  if calls % 64 == 0 then k.event.pull(0) end
end

local function colour(word)
  local c = tonumber(word or 1)
  if not c or c < 1 or c > 3 or c % 1 ~= 0 then return nil end
  return depth < 2 and 1 or c
end

-- ---- letters -----------------------------------------------------------------------
-- 5 x 7 glyphs, one number per row from the top; bit 16 is the left column
local FONT = {
  A = { 14, 17, 17, 31, 17, 17, 17 }, B = { 30, 17, 17, 30, 17, 17, 30 }, C = { 14, 17, 16, 16, 16, 17, 14 },
  D = { 28, 18, 17, 17, 17, 18, 28 }, E = { 31, 16, 16, 30, 16, 16, 31 }, F = { 31, 16, 16, 30, 16, 16, 16 },
  G = { 14, 17, 16, 23, 17, 17, 15 }, H = { 17, 17, 17, 31, 17, 17, 17 }, I = { 14, 4, 4, 4, 4, 4, 14 },
  J = { 7, 2, 2, 2, 2, 18, 12 }, K = { 17, 18, 20, 24, 20, 18, 17 }, L = { 16, 16, 16, 16, 16, 16, 31 },
  M = { 17, 27, 21, 21, 17, 17, 17 }, N = { 17, 17, 25, 21, 19, 17, 17 }, O = { 14, 17, 17, 17, 17, 17, 14 },
  P = { 30, 17, 17, 30, 16, 16, 16 }, Q = { 14, 17, 17, 17, 21, 18, 13 }, R = { 30, 17, 17, 30, 20, 18, 17 },
  S = { 15, 16, 16, 14, 1, 1, 30 }, T = { 31, 4, 4, 4, 4, 4, 4 }, U = { 17, 17, 17, 17, 17, 17, 14 },
  V = { 17, 17, 17, 17, 17, 10, 4 }, W = { 17, 17, 17, 21, 21, 21, 10 }, X = { 17, 17, 10, 4, 10, 17, 17 },
  Y = { 17, 17, 17, 10, 4, 4, 4 }, Z = { 31, 1, 2, 4, 8, 16, 31 },
  ["0"] = { 14, 17, 19, 21, 25, 17, 14 }, ["1"] = { 4, 12, 4, 4, 4, 4, 14 }, ["2"] = { 14, 17, 1, 2, 4, 8, 31 },
  ["3"] = { 31, 2, 4, 2, 1, 17, 14 }, ["4"] = { 2, 6, 10, 18, 31, 2, 2 }, ["5"] = { 31, 16, 30, 1, 1, 17, 14 },
  ["6"] = { 6, 8, 16, 30, 17, 17, 14 }, ["7"] = { 31, 1, 2, 4, 8, 8, 8 }, ["8"] = { 14, 17, 17, 14, 17, 17, 14 },
  ["9"] = { 14, 17, 17, 15, 1, 2, 12 }, [" "] = { 0, 0, 0, 0, 0, 0, 0 },
  ["!"] = { 4, 4, 4, 4, 4, 0, 4 }, ["?"] = { 14, 17, 1, 2, 4, 0, 4 }, ["."] = { 0, 0, 0, 0, 0, 12, 12 },
  ["-"] = { 0, 0, 0, 31, 0, 0, 0 }, [":"] = { 0, 12, 12, 0, 12, 12, 0 },
}

-- Draws text centred; returns how many characters fitted.
local function text(s, c)
  s = s:upper()
  local fits = math.min(#s, (W + 1) // 6)
  s = s:sub(1, fits)
  local width = #s * 6 - 1
  local scale = math.max(1, math.min(W // math.max(width, 1), H // 7, 4))
  local x0 = (W - width * scale) // 2 + 1
  local y0 = (H - 7 * scale) // 2 + 1
  local thick = math.max(2, scale * 2)
  local z0 = (D - thick) // 2 + 1
  for i = 1, #s do
    local glyph = FONT[s:sub(i, i)] or FONT["?"]
    for col = 1, 5 do
      local bit = 1 << (5 - col)
      -- runs of lit rows in this column become one fill each
      local row = 1
      while row <= 7 do
        if glyph[row] & bit ~= 0 then
          local last = row
          while last < 7 and glyph[last + 1] & bit ~= 0 do last = last + 1 end
          local ylow = y0 + (7 - last) * scale
          local yhigh = y0 + (7 - row) * scale + scale - 1
          for sx = 0, scale - 1 do
            local x = x0 + ((i - 1) * 6 + col - 1) * scale + sx
            for z = z0, z0 + thick - 1 do fill(x, z, ylow, yhigh, c) end
          end
          row = last + 1
        else
          row = row + 1
        end
      end
    end
  end
  return fits
end

-- ---- shapes -----------------------------------------------------------------------------
-- centred on the middle of the projector (between voxels 24 and 25)
local CX, CY, CZ = (W + 1) / 2, (H + 1) / 2, (D + 1) / 2

local function shape(kind, size, c)
  local half = size / 2
  for x = 1, W do
    for z = 1, D do
      local dx, dz = x - CX, z - CZ
      if kind == "cube" then
        if math.abs(dx) < half and math.abs(dz) < half then
          fill(x, z, math.floor(CY - half + 0.5), math.floor(CY + half - 0.5), c)
        end
      elseif kind == "sphere" then
        local d2 = dx * dx + dz * dz
        if d2 < half * half then
          local dy = math.sqrt(half * half - d2)
          fill(x, z, math.max(1, math.ceil(CY - dy)), math.min(H, math.floor(CY + dy)), c)
        end
      else -- pyramid: the base on the floor of the box, the tip size/2 above it
        local m = math.max(math.abs(dx), math.abs(dz))
        if m < half then
          local base = math.floor(CY - half / 2 + 0.5)
          local top = base + math.floor((half - m) + 0.5) - 1
          fill(x, z, math.max(1, base), math.min(H, top), c)
        end
      end
    end
  end
end

-- ---- the command -------------------------------------------------------------------------
local cmd = args[1]
if cmd == "clear" then
  h.clear()
  return 0
elseif cmd == "text" then
  local s = args[2]
  if not s or s == "" then return fail("usage: holo text \"TEXT\" [COLOR]") end
  local c = colour(args[3]); if not c then return fail("COLOR is 1, 2 or 3") end
  h.clear()
  local fitted = text(s, c)
  if fitted < #s then term.write(("holo: only the first %d characters fit\n"):format(fitted)) end
  return 0
elseif cmd == "shape" then
  local kind = args[2]
  if kind ~= "cube" and kind ~= "sphere" and kind ~= "pyramid" then return fail("shape is cube, sphere or pyramid") end
  local size = tonumber(args[3] or 16)
  if not size or size < 1 or size > H or size % 1 ~= 0 then return fail("SIZE is 1-" .. H) end
  local c = colour(args[4]); if not c then return fail("COLOR is 1, 2 or 3") end
  h.clear()
  shape(kind, size, c)
  return 0
elseif cmd == "color" or cmd == "colour" then
  local n, value = tonumber(args[2]), tonumber(args[3] or "")
  if not n or n < 1 or n > 3 or not value or value < 0 or value > 0xFFFFFF then
    return fail("usage: holo color N 0xRRGGBB (N is 1-3)")
  end
  if depth < 2 and n > 1 then return fail("a tier 1 projector has only colour 1") end
  h.setPaletteColor(n, math.floor(value))
  return 0
elseif cmd == "scale" then
  local s = tonumber(args[2] or "")
  if not s or s < 0.33 or s > 3 then return fail("the scale is 0.33 - 3") end
  h.setScale(s)
  return 0
elseif cmd == "spin" then
  local speed = tonumber(args[2] or 30)
  if not speed then return fail("usage: holo spin [DEGREES PER SECOND]") end
  if depth < 2 or not h.setRotationSpeed then return fail("only a tier 2 projector can spin") end
  h.setRotationSpeed(speed, 0, 1, 0)
  return 0
elseif cmd == "demo" then
  h.clear()
  if depth >= 2 then
    h.setPaletteColor(1, 0x1793D1); h.setPaletteColor(2, 0x5FD068); h.setPaletteColor(3, 0xE8C061)
  end
  text("BYTEOS", colour(1))
  if depth >= 2 and h.setRotationSpeed then h.setRotationSpeed(20, 0, 1, 0) end
  return 0
end
term.write("usage: holo clear | text \"TEXT\" [COLOR] | shape cube|sphere|pyramid [SIZE] [COLOR]\n"
  .. "            | color N 0xRRGGBB | scale S | spin [SPEED] | demo   (man holo)\n")
return 2
