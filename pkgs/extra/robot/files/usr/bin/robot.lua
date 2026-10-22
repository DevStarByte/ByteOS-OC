--[[
  robot - drive an OpenComputers robot (or a drone) from the shell

    robot move forward|back|up|down [N]   N steps (default 1)
    robot turn left|right|around
    robot dig|place|use [front|up|down]   swing the tool, place the selected
                                          block, right-click (default front)
    robot detect                          what is in front, above and below
    robot select N                        pick inventory slot N
    robot drop|suck [N] [front|up|down]   drop / take N items (default all)
    robot info                            name, energy, tool, inventory
    robot run FILE                        run the steps in FILE, one per line

    robot drone move DX DY DZ             fly a drone by that offset
    robot drone info                      its name, offset and speed

  A step file holds the commands above without the word robot, # starts a
  comment, and repeat N ... end runs the lines between N times:

    # dig a tunnel 10 blocks long
    repeat 10
      dig
      move forward
    end
    turn around

  It stops at the first step that fails ("line 4: move forward: something
  is in the way") with status 1. Only on a robot (or with a drone near a
  computer that controls it); OpenComputers' own reason is shown when a
  move is blocked.
]]--
local T = term.theme
local args = arg or {}

local SIDE = { down = 0, up = 1, back = 2, front = 3, forward = 3 }

local function fail(msg) term.cwrite(T.err, "robot: "); term.write(msg .. "\n"); return 1 end

local function proxyOf(kind)
  local addr = component.list(kind)()
  return addr and component.proxy(addr)
end

-- One step: words such as { "move", "forward", "3" }. Returns true or
-- nil, why.
local function step(r, w)
  local cmd = w[1]
  if cmd == "move" then
    local dir = w[2] or "forward"
    local side = SIDE[dir]
    if not side then return nil, "move where? forward, back, up or down" end
    local n = tonumber(w[3] or 1)
    if not n or n < 1 then return nil, "not a number of steps: " .. tostring(w[3]) end
    for i = 1, n do
      local ok, why = r.move(side)
      if not ok then
        return nil, ("move %s: %s%s"):format(dir, tostring(why or "blocked"),
          n > 1 and (" (after " .. (i - 1) .. " of " .. n .. " steps)") or "")
      end
    end
    return true
  elseif cmd == "turn" then
    local dir = w[2]
    if dir == "left" then r.turn(false)
    elseif dir == "right" then r.turn(true)
    elseif dir == "around" then r.turn(true); r.turn(true)
    else return nil, "turn which way? left, right or around" end
    return true
  elseif cmd == "dig" or cmd == "place" or cmd == "use" then
    local where = w[2] or "front"
    local side = SIDE[where]
    if not side or side == 2 then return nil, cmd .. " where? front, up or down" end
    local fn = r[cmd == "dig" and "swing" or cmd]
    local ok, why = fn(side)
    if not ok then return nil, ("%s %s: %s"):format(cmd, where, tostring(why or "nothing happened")) end
    return true
  elseif cmd == "detect" then
    for _, s in ipairs({ "front", "up", "down" }) do
      local solid, what = r.detect(SIDE[s])
      term.write(("%-6s %s\n"):format(s, tostring(what or (solid and "solid" or "air"))))
    end
    return true
  elseif cmd == "select" then
    local n = tonumber(w[2])
    local size = r.inventorySize and r.inventorySize() or 0
    if not n or n < 1 or (size > 0 and n > size) then return nil, "select a slot from 1 to " .. size end
    r.select(n)
    return true
  elseif cmd == "drop" or cmd == "suck" then
    local count, where = tonumber(w[2]), w[2]
    if count then where = w[3] end
    where = where or "front"
    local side = SIDE[where]
    if not side or side == 2 then return nil, cmd .. " where? front, up or down" end
    local ok, why = r[cmd](side, count)
    if not ok then return nil, ("%s %s: %s"):format(cmd, where, tostring(why or "nothing to " .. cmd)) end
    return true
  elseif cmd == "info" then
    term.cwrite(T.bright, (r.name and r.name() or "robot") .. "\n")
    term.write(("energy   %d / %d\n"):format(math.floor(computer.energy()), math.floor(computer.maxEnergy())))
    local dur, why = nil, "no tool"
    if r.durability then dur, why = r.durability() end
    term.write("tool     " .. (dur and ("%d%% left"):format(math.floor(dur * 100 + 0.5)) or tostring(why)) .. "\n")
    local size = r.inventorySize and r.inventorySize() or 0
    local selected = r.select and r.select() or 0
    term.write(("slots    %d (slot %d selected)\n"):format(size, selected))
    for s = 1, size do
      local c = r.count(s)
      if c > 0 or s == selected then
        term.cwrite(s == selected and T.accent or T.fg, ("  %2d  %3d items%s\n"):format(s, c, s == selected and "  <" or ""))
      end
    end
    return true
  end
  return nil, "unknown step '" .. tostring(cmd) .. "' (see man robot)"
end

-- A step file as a list of { line = n, words = {...} } and { line, rep = n, body = {...} }.
local function parse(text)
  local stack = { { body = {} } }
  local n = 0
  for raw in (text .. "\n"):gmatch("([^\n]*)\n") do
    n = n + 1
    local line = raw:gsub("#.*$", ""):gsub("\r", "")
    local words = {}
    for word in line:gmatch("%S+") do words[#words + 1] = word end
    if words[1] == "repeat" then
      local times = tonumber(words[2])
      if not times or times < 0 then return nil, "line " .. n .. ": repeat needs a number" end
      local block = { line = n, rep = math.floor(times), body = {} }
      table.insert(stack[#stack].body, block)
      stack[#stack + 1] = block
    elseif words[1] == "end" then
      if #stack == 1 then return nil, "line " .. n .. ": 'end' without 'repeat'" end
      stack[#stack] = nil
    elseif #words > 0 then
      if words[1] == "run" then return nil, "line " .. n .. ": a step file cannot run another" end
      table.insert(stack[#stack].body, { line = n, words = words })
    end
  end
  if #stack > 1 then return nil, "line " .. stack[#stack].line .. ": 'repeat' without 'end'" end
  return stack[1].body
end

local calls = 0
local function runList(r, list)
  for _, s in ipairs(list) do
    if s.rep then
      for _ = 1, s.rep do
        local ok, why = runList(r, s.body)
        if not ok then return nil, why end
      end
    else
      local ok, why = step(r, s.words)
      if not ok then return nil, "line " .. s.line .. ": " .. why end
      calls = calls + 1
      if calls % 16 == 0 then k.event.pull(0) end -- let the machine breathe
    end
  end
  return true
end

-- ---- drones ------------------------------------------------------------------
local function drone(w)
  local d = proxyOf("drone")
  if not d then return fail("no drone here (this runs on a drone, or a computer with one in reach)") end
  if w[1] == "move" then
    local dx, dy, dz = tonumber(w[2]), tonumber(w[3]), tonumber(w[4])
    if not (dx and dy and dz) then return fail("usage: robot drone move DX DY DZ") end
    d.move(dx, dy, dz)
    return 0
  elseif w[1] == "info" or not w[1] then
    term.cwrite(T.bright, (d.name and d.name() or "drone") .. "\n")
    if d.getOffset then term.write(("offset   %.1f (distance to where it is flying)\n"):format(d.getOffset())) end
    if d.getVelocity then term.write(("speed    %.1f blocks/s\n"):format(d.getVelocity())) end
    term.write(("energy   %d / %d\n"):format(math.floor(computer.energy()), math.floor(computer.maxEnergy())))
    return 0
  end
  return fail("usage: robot drone move DX DY DZ | robot drone info")
end

-- ---- the command -----------------------------------------------------------------
if #args == 0 then term.write("usage: robot move|turn|dig|place|use|detect|select|drop|suck|info|run|drone ... (man robot)\n"); return 2 end
if args[1] == "drone" then return drone({ table.unpack(args, 2) }) end

local r = proxyOf("robot")
if not r then return fail("this is not a robot (no robot component)") end

if args[1] == "run" then
  if not args[2] then return fail("usage: robot run FILE") end
  local text, err = fs.readAll(shell.normalize(args[2]))
  if not text then return fail(args[2] .. ": " .. tostring(err or "cannot read")) end
  local list, perr = parse(text)
  if not list then return fail(args[2] .. ": " .. perr) end
  local ok, why = runList(r, list)
  if not ok then return fail(args[2] .. ", " .. why) end
  return 0
end

local ok, why = step(r, args)
if not ok then return fail(why) end
return 0
