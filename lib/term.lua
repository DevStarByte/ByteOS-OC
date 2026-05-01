--[[
  /lib/term.lua - terminal driver for ByteOS
  Wraps GPU + screen + keyboard into print/read/clear primitives.
]]--

local component = component
local computer  = computer
local k         = _G.kernel

local term = {}

local gpu      = component.proxy(component.list("gpu")())
local screen   = component.list("screen")()
if gpu and screen then gpu.bind(screen) end
local keyboard = component.list("keyboard")()

term.gpu = gpu
local W, H = gpu.getResolution()
term.width, term.height = W, H

local cx, cy = 1, 1

local function scrollIfNeeded()
  if cy > H then
    gpu.copy(1, 2, W, H - 1, 0, -1)
    gpu.fill(1, H, W, 1, " ")
    cy = H
  end
end

function term.clear()
  gpu.setBackground(0x000000)
  gpu.setForeground(0xFFFFFF)
  gpu.fill(1, 1, W, H, " ")
  cx, cy = 1, 1
end

function term.setCursor(x, y) cx, cy = x, y end
function term.getCursor() return cx, cy end
function term.size() return W, H end
function term.setForeground(c) gpu.setForeground(c) end
function term.setBackground(c) gpu.setBackground(c) end

function term.write(s)
  s = tostring(s)
  for i = 1, #s do
    local ch = s:sub(i, i)
    if ch == "\n" then
      cx, cy = 1, cy + 1
      scrollIfNeeded()
    elseif ch == "\r" then
      cx = 1
    elseif ch == "\t" then
      local advance = 4 - ((cx - 1) % 4)
      gpu.set(cx, cy, string.rep(" ", advance))
      cx = cx + advance
    else
      gpu.set(cx, cy, ch)
      cx = cx + 1
      if cx > W then cx, cy = 1, cy + 1; scrollIfNeeded() end
    end
  end
end

function term.print(...)
  local args = { ... }
  for i = 1, select("#", ...) do
    if i > 1 then term.write("\t") end
    term.write(tostring(args[i]))
  end
  term.write("\n")
end
_G.print = term.print

function term.read(opts)
  opts = opts or {}
  local buf = ""
  local startX, startY = cx, cy
  local function redraw()
    gpu.fill(startX, startY, W - startX + 1, 1, " ")
    cx, cy = startX, startY
    if opts.mask then
      term.write(string.rep(opts.mask, #buf))
    else
      term.write(buf)
    end
  end
  while true do
    local ev, _, ch, code = k.event.pull(nil)
    if ev == "key_down" then
      if code == 28 then -- enter
        term.write("\n")
        return buf
      elseif code == 14 then -- backspace
        if #buf > 0 then buf = buf:sub(1, -2); redraw() end
      elseif ch and ch >= 32 and ch < 127 then
        buf = buf .. string.char(ch)
        if opts.mask then term.write(opts.mask) else term.write(string.char(ch)) end
      end
    elseif ev == "interrupted" then
      return nil
    end
  end
end
_G.read = term.read

return term
