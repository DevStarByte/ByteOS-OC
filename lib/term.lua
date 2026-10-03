--[[
  /lib/term.lua - the terminal: write, print, read, colours, the cursor

  The screen's terminal (lib/tty.lua) on the GPU, with the shared colour
  theme (lib/theme.lua) loaded into its palette. Every call goes to the
  terminal of the running process: the screen, or the window it runs in.
]]--

local component = component
local tty       = require("tty")
local theme     = require("theme")

local gpu      = component.proxy(component.list("gpu")())
local screen   = component.list("screen")()
if gpu and screen then
  gpu.bind(screen)
  if gpu.maxDepth then
    local maxDepth = gpu.maxDepth()
    if gpu.getDepth() < maxDepth then gpu.setDepth(maxDepth) end
  end
end

local console = tty.new(gpu)
if console.depth >= 4 then console.setPalette(theme.palette)
else theme.monochrome() end

return tty.term(console)
