-- The device packages robot and holo (extra), driven against fake
-- components that record what they are asked to do.
users()
local P = dofile(REPO .. "/tools/test/pkgrepo.lua")
if not P then return end

test("robot and holo install", function()
  local out = run(P .. "-S robot holo")
  lacks(out, "error")
  ok(file("/usr/bin/robot.lua") and file("/usr/bin/holo.lua"), "both commands are there")
end)

-- ---- robot ------------------------------------------------------------------------
-- A robot whose moves fail after `blockAfter` of them, with a few items.
local function fakeRobot(blockAfter)
  local log, slots, sel, moves = {}, { 5, 0, 12, 0 }, 1, 0
  local function note(s) log[#log + 1] = s end
  local r = {
    name = function() return "Tunneler" end,
    move = function(side)
      moves = moves + 1
      if blockAfter and moves > blockAfter then return false, "something is in the way" end
      note("move " .. side); return true
    end,
    turn = function(cw) note("turn " .. tostring(cw)); return true end,
    swing = function(side) note("swing " .. side); return true end,
    use = function(side) note("use " .. side); return true end,
    place = function(side) note("place " .. side); if side == 0 then return false, "nothing to place" end return true end,
    detect = function(side) if side == 3 then return true, "solid" end return false, "air" end,
    select = function(n) if n then sel = n; note("select " .. n) end return sel end,
    count = function(s) return slots[s] or 0 end,
    inventorySize = function() return 4 end,
    durability = function() return 0.75 end,
    drop = function(side, n) note("drop " .. side .. " " .. tostring(n)); return true end,
    suck = function(side, n) note("suck " .. side .. " " .. tostring(n)); return false end,
  }
  return r, log
end

test("robot: not on a robot", function()
  local out, rc = run("robot move")
  has(out, "this is not a robot"); eq(rc, 1)
  has(run("robot"), "usage: robot")
end)

test("robot: moving, turning, tools and the inventory", function()
  local r, log = fakeRobot()
  plug("robot", "robot000-1", r)
  local out = {}
  for _, line in ipairs({ "robot move forward 3", "robot move up", "robot move back", "robot turn around",
                          "robot turn left", "robot dig up", "robot use", "robot place", "robot select 3",
                          "robot drop 5 up", "robot drop", "robot detect", "robot info" }) do
    out[#out + 1] = run(line)
  end
  local sucked, suckRc = run("robot suck down")
  local bad, badRc = run("robot place down")
  local nope = run("robot fly")
  undisk("robot000-1")
  eq(table.concat(log, ","), "move 3,move 3,move 3,move 1,move 2,turn true,turn true,turn false,"
    .. "swing 1,use 3,place 3,select 3,drop 1 5,drop 3 nil,suck 0 nil,place 0")
  has(out[12], "front  solid"); has(out[12], "up     air")
  has(out[13], "Tunneler"); has(out[13], "tool     75% left"); has(out[13], "slots    4 (slot 3 selected)")
  has(out[13], "   1    5 items"); has(out[13], "   3   12 items  <")
  eq(suckRc, 1); has(sucked, "suck down: nothing to suck")
  eq(badRc, 1); has(bad, "place down: nothing to place")
  has(nope, "unknown step 'fly'")
end)

test("robot: a blocked move says why and how far it got", function()
  local r = fakeRobot(2)
  plug("robot", "robot000-1", r)
  local out, rc = run("robot move forward 5")
  undisk("robot000-1")
  eq(rc, 1)
  has(out, "move forward: something is in the way (after 2 of 5 steps)")
end)

test("robot run: step files with repeat, stopping at the first failure", function()
  put("/tmp/tunnel.txt", "# a short tunnel\nrepeat 3\n  dig\n  move forward\nend\nturn around  # and back\n")
  local r, log = fakeRobot()
  plug("robot", "robot000-1", r)
  local _, rc = run("robot run /tmp/tunnel.txt")
  undisk("robot000-1")
  eq(rc, 0)
  eq(table.concat(log, ","), "swing 3,move 3,swing 3,move 3,swing 3,move 3,turn true,turn true")

  r = fakeRobot(1)
  plug("robot", "robot000-1", r)
  local out, frc = run("robot run /tmp/tunnel.txt")
  undisk("robot000-1")
  eq(frc, 1); has(out, "/tmp/tunnel.txt, line 4: move forward: something is in the way")

  put("/tmp/bad1.txt", "move\nend\n")
  put("/tmp/bad2.txt", "repeat 2\n  move\n")
  put("/tmp/bad3.txt", "repeat x\nend\n")
  plug("robot", "robot000-1", fakeRobot())
  local b1, b2, b3 = run("robot run /tmp/bad1.txt"), run("robot run /tmp/bad2.txt"), run("robot run /tmp/bad3.txt")
  local missing = run("robot run /tmp/nope.txt")
  undisk("robot000-1")
  has(b1, "line 2: 'end' without 'repeat'"); has(b2, "line 1: 'repeat' without 'end'")
  has(b3, "line 1: repeat needs a number"); has(missing, "/tmp/nope.txt")
end)

test("robot drone: move and info", function()
  has(run("robot drone info"), "no drone here")
  local moved
  plug("drone", "drone000-1", {
    name = function() return "Scout" end,
    move = function(dx, dy, dz) moved = dx .. " " .. dy .. " " .. dz end,
    getOffset = function() return 2.5 end,
    getVelocity = function() return 1 end,
  })
  local _, rc = run("robot drone move 1 2 -3")
  local info = run("robot drone info")
  local bad = run("robot drone move 1 x")
  undisk("drone000-1")
  eq(rc, 0); eq(moved, "1 2 -3")
  has(info, "Scout"); has(info, "offset   2.5"); has(info, "speed    1.0")
  has(bad, "usage: robot drone move DX DY DZ")
end)

-- ---- holo ---------------------------------------------------------------------------
-- A projector of the given tier (1: one colour, 2: three) keeping its voxels.
local function fakeHolo(depth)
  local st = { vox = {}, log = {}, calls = 0 }
  local function note(s) st.log[#st.log + 1] = s end
  st.proxy = {
    clear = function() st.vox = {}; note("clear") end,
    fill = function(x, z, a, b, v)
      st.calls = st.calls + 1
      assert(x >= 1 and x <= 48 and z >= 1 and z <= 48 and a >= 1 and b <= 32, "outside the projector")
      for y = a, b do st.vox[x .. "," .. y .. "," .. z] = v end
    end,
    set = function(x, y, z, v) st.vox[x .. "," .. y .. "," .. z] = v end,
    maxDepth = function() return depth end,
    setPaletteColor = function(i, c) note(("palette %d %06x"):format(i, c)) end,
    setScale = function(s) note("scale " .. s) end,
    setRotationSpeed = function(s, x, y, z) note(("spin %s %d %d %d"):format(s, x, y, z)) end,
  }
  return st
end
local function count(vox) local n = 0 for _ in pairs(vox) do n = n + 1 end return n end
local function at(st, x, y, z) return st.vox[x .. "," .. y .. "," .. z] end

test("holo: no projector", function()
  has(run("holo clear"), "no hologram projector")
end)

test("holo text: letters at the right voxels, centred, in columns", function()
  local st = fakeHolo(2)
  plug("hologram", "holo0000-1", st.proxy)
  local _, rc = run("holo text I 2")
  undisk("holo0000-1")
  eq(rc, 0)
  -- "I" is 5 x 7, drawn 4 times as big (20 x 28), 8 deep, centred:
  -- x 15-34, y 3-30, z 21-28; its middle column is lit all the way
  eq(count(st.vox), 1408)
  eq(at(st, 23, 3, 21), 2); eq(at(st, 26, 30, 28), 2)
  eq(at(st, 23, 31, 21), nil); eq(at(st, 15, 10, 24), nil)
  eq(at(st, 19, 27, 24), 2, "the top bar"); eq(at(st, 19, 10, 24), nil, "no left stem")
  for key in pairs(st.vox) do
    local x, y, z = key:match("(%d+),(%d+),(%d+)")
    ok(at(st, 49 - tonumber(x), y, z), "mirrored across the middle: " .. key)
  end
  eq(st.calls, 160, "one fill per lit run of a column, not one call per voxel (1408)")
end)

test("holo text: too long, and colours on a tier 1 projector", function()
  local st = fakeHolo(1)
  plug("hologram", "holo0000-1", st.proxy)
  local long = run("holo text ABCDEFGHIJ")
  local _, rc = run("holo text HI 3")
  local tier1 = run("holo color 2 0xFF0000")
  local spin = run("holo spin")
  undisk("holo0000-1")
  has(long, "only the first 8 characters fit")
  eq(rc, 0)
  for _, v in pairs(st.vox) do eq(v, 1, "a tier 1 projector has one colour") end
  has(tier1, "a tier 1 projector has only colour 1")
  has(spin, "only a tier 2 projector can spin")
end)

test("holo shapes are sized right and symmetric", function()
  local st = fakeHolo(2)
  plug("hologram", "holo0000-1", st.proxy)
  run("holo shape cube 16")
  local cube = count(st.vox)
  local cubeCorner, cubeOut = at(st, 17, 9, 17), at(st, 16, 9, 17)
  run("holo shape sphere 16 3")
  local sphere = st.vox
  run("holo shape pyramid 16")
  local pyramid = st.vox
  local bad = run("holo shape blob")
  undisk("holo0000-1")
  eq(cube, 16 * 16 * 16); eq(cubeCorner, 1); eq(cubeOut, nil)
  local minX, maxX = 99, 0
  for key, v in pairs(sphere) do
    local x, y, z = key:match("(%d+),(%d+),(%d+)")
    x, y, z = tonumber(x), tonumber(y), tonumber(z)
    eq(v, 3)
    ok(sphere[(49 - x) .. "," .. (33 - y) .. "," .. (49 - z)], "the sphere is symmetric: " .. key)
    minX, maxX = math.min(minX, x), math.max(maxX, x)
  end
  eq(minX, 17); eq(maxX, 32)
  local base, tip = 0, 0
  for key in pairs(pyramid) do
    local y = tonumber(key:match(",(%d+),"))
    if y == 13 then base = base + 1 end
    if y == 20 then tip = tip + 1 end
  end
  eq(base, 16 * 16, "the base is the full 16 x 16"); eq(tip, 4, "the tip is the middle 2 x 2")
  has(bad, "shape is cube, sphere or pyramid")
end)

test("holo color, scale, spin and demo", function()
  local st = fakeHolo(2)
  plug("hologram", "holo0000-1", st.proxy)
  run("holo color 2 0xFF8800"); run("holo scale 2"); run("holo spin 45")
  local badScale = run("holo scale 9")
  run("holo demo")
  undisk("holo0000-1")
  has(table.concat(st.log, ","), "palette 2 ff8800,scale 2,spin 45 0 1 0")
  has(badScale, "the scale is 0.33 - 3")
  has(table.concat(st.log, ","), "spin 20 0 1 0")
  ok(count(st.vox) > 0, "the demo draws something")
end)
