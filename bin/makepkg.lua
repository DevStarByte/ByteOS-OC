--[[
  makepkg - build a .bpk package from its source directory

    makepkg [dir]     build the package in dir (default: current directory)

  The directory holds PKGBUILD.lua, an optional install file and files/
  (see /lib/bpk.lua). The package is written next to PKGBUILD.lua as
  <name>-<version>.bpk; install it with `pacman -U <file>`.
]]--

local bpk  = require("bpk")
local fs   = k.fs
local args = arg or {}
local T    = term.theme

local function arrow(color, msg)
  term.cwrite(color, "==> ")
  term.cwrite(T.bright, msg .. "\n")
end

if args[1] == "-h" or args[1] == "--help" then
  term.write("usage: makepkg [dir]\n")
  return 0
end

local dir = shell.normalize(args[1] or _G.PWD or "/")
local entries, info = bpk.build(dir, fs)
if not entries then
  arrow(T.err, "ERROR: " .. tostring(info))
  return 1
end
arrow(T.green, ("Making package: %s %s"):format(info.name, info.version))
term.cwrite(T.muted, ("  -> %d file%s, %d bytes\n"):format(#entries - 1, #entries == 2 and "" or "s", info.isize))

local out = dir .. "/" .. bpk.filename(info)
local h, e = fs.open(out, "w")
if not h then
  arrow(T.err, "ERROR: cannot write " .. out .. ": " .. tostring(e))
  return 1
end
bpk.write(h, entries)
h:close()
arrow(T.green, ("Finished making: %s (%d bytes)"):format(bpk.filename(info), fs.size(out)))
term.cwrite(T.muted, "  install it with ")
term.cwrite(T.blue, "pacman -U " .. out .. "\n")
return 0
