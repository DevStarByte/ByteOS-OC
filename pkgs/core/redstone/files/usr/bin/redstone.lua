--[[
  redstone - read and set redstone signals (a redstone card or I/O block)

    redstone                          every side: input and output
    redstone get <side>               the input on one side (0-15)
    redstone set <side> <0-15>        set the output (root)
    redstone bundled <side>           a bundled cable's 16 colours
    redstone bundled <side> <colour> <0-255>   set one colour (root)

  sides:   bottom top back front right left (or 0-5)
  colours: white orange magenta lightblue yellow lime pink gray silver
           cyan purple blue brown green red black (or 0-15)
]]--
local T = term.theme
local args = arg or {}
local SIDES = { "bottom", "top", "back", "front", "right", "left" }
local COLOURS = { "white", "orange", "magenta", "lightblue", "yellow", "lime", "pink", "gray",
                  "silver", "cyan", "purple", "blue", "brown", "green", "red", "black" }

local addr = component.list("redstone")()
if not addr then term.write("redstone: no redstone card or redstone I/O block\n"); return 1 end
local rs = component.proxy(addr)

local function pick(list, word, what)
  local n = tonumber(word)
  if n and list[n + 1] then return n end
  for i, name in ipairs(list) do if name == word then return i - 1 end end
  term.write("redstone: unknown " .. what .. " '" .. tostring(word) .. "'\n")
  return nil
end
local function needRoot()
  if k.user() ~= "root" then term.write("redstone: only root may set outputs (try sudo)\n"); return false end
  return true
end

local cmd = args[1]
if not cmd then
  term.cwrite(T.bright, ("%-8s %5s %6s\n"):format("SIDE", "IN", "OUT"))
  for i, name in ipairs(SIDES) do
    term.write(("%-8s %5d %6d\n"):format(name, rs.getInput(i - 1) or 0, rs.getOutput(i - 1) or 0))
  end
  return 0
elseif cmd == "get" then
  local side = pick(SIDES, args[2], "side"); if not side then return 1 end
  term.write((rs.getInput(side) or 0) .. "\n")
  return 0
elseif cmd == "set" then
  local side = pick(SIDES, args[2], "side"); if not side then return 1 end
  local level = tonumber(args[3])
  if not level or level < 0 or level > 15 then term.write("redstone: the level is 0-15\n"); return 1 end
  if not needRoot() then return 1 end
  rs.setOutput(side, math.floor(level))
  return 0
elseif cmd == "bundled" then
  local side = pick(SIDES, args[2], "side"); if not side then return 1 end
  if not rs.getBundledInput then term.write("redstone: this card has no bundled cable support (tier 2 needed)\n"); return 1 end
  if args[3] then
    local colour = pick(COLOURS, args[3], "colour"); if not colour then return 1 end
    local level = tonumber(args[4])
    if not level or level < 0 or level > 255 then term.write("redstone: the level is 0-255\n"); return 1 end
    if not needRoot() then return 1 end
    rs.setBundledOutput(side, colour, math.floor(level))
    return 0
  end
  term.cwrite(T.bright, ("%-10s %5s %6s\n"):format("COLOUR", "IN", "OUT"))
  for i, name in ipairs(COLOURS) do
    term.write(("%-10s %5d %6d\n"):format(name, rs.getBundledInput(side, i - 1) or 0, rs.getBundledOutput(side, i - 1) or 0))
  end
  return 0
end
term.write("usage: redstone [get <side> | set <side> <0-15> | bundled <side> [<colour> <0-255>]]\n")
return 1
