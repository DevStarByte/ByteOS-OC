--[[
  chmod [-R] MODE FILE... - change who may read, write or run files

    MODE is octal (755, 640) or symbolic: [ugoa][+-=][rwx], several
    joined by commas: u+x  go-w  a=r  +x  u=rw,go=r
      u the owner   g the group   o others   a (or nothing) all three
    -R  also everything inside directories

  Only root and the file's owner may change its mode. ls -l shows it.
]]--
local args = arg or {}
local recursive, mode, files = false, nil, {}
for _, a in ipairs(args) do
  if a == "-R" then recursive = true
  elseif not mode then mode = a
  else files[#files + 1] = a end
end
if not mode or #files == 0 then term.write("usage: chmod [-R] MODE FILE...\n"); return 1 end

local WHO = { u = 448, g = 56, o = 7 }      -- 0700 0070 0007
local BITS = { r = 292, w = 146, x = 73 }   -- 0444 0222 0111 (masked by who)

-- The new mode for a file whose mode is now `old`; nil if MODE is invalid.
local function apply(old)
  if mode:match("^[0-7]+$") then return tonumber(mode, 8) end
  local new = old
  for clause in mode:gmatch("[^,]+") do
    local who, op, perms = clause:match("^([ugoa]*)([%+%-=])([rwx]*)$")
    if not who then return nil end
    local mask = 0
    if who == "" or who:find("a") then mask = 511 end
    for c in who:gmatch("[ugo]") do mask = mask | WHO[c] end
    local bits = 0
    for c in perms:gmatch(".") do bits = bits | BITS[c] end
    bits = bits & mask
    if op == "+" then new = new | bits
    elseif op == "-" then new = new & ~bits
    else new = (new & ~mask) | bits end
  end
  return new
end
if not apply(0) then term.write("chmod: invalid mode '" .. mode .. "'\n"); return 1 end

local rc = 0
local function change(path, shown)
  local ok, err = fs.chmod(path, apply(fs.stat(path).mode))
  if not ok then term.write("chmod: " .. shown .. ": " .. tostring(err) .. "\n"); rc = 1; return end
  if recursive and fs.isDirectory(path) then
    for _, e in ipairs(fs.list(path) or {}) do
      local name = e:gsub("/$", "")
      change(path .. "/" .. name, shown .. "/" .. name)
    end
  end
end
for _, f in ipairs(files) do change(shell.normalize(f), f) end
return rc
