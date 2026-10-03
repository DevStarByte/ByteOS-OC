-- neofetch - the ByteOS logo with system information
local T = term.theme
local W, H = term.size()

local BIG = {
  "                  -`",
  "                 .o+`",
  "                `ooo/",
  "               `+oooo:",
  "              `+oooooo:",
  "              -+oooooo+:",
  "            `/:-:++oooo+:",
  "           `/++++/+++++++:",
  "          `/++++++++++++++:",
  "         `/+++ooooooooooooo/`",
  "        ./ooosssso++osssssso+`",
  "       .oossssso-````/ossssss+`",
  "      -osssssso.      :ssssssso.",
  "     :osssssss/        osssso+++.",
  "    /ossssssss/        +ssssooo/-",
  "  `/ossssso+/:-        -:/+osssso+-",
  " `+sso+:-`                 `.-/+oso:",
  "`++:.                           `-/+/",
  ".`                                 `/",
}
local SMALL = {
  "      /\\",
  "     /  \\",
  "    /\\   \\",
  "   /      \\",
  "  /   ,,   \\",
  " /   |  |  -\\",
  "/_-''    ''-_\\",
}

-- ---- gather info -----------------------------------------------------------
local function human(bytes)
  if bytes >= 1024 * 1024 then return ("%.1f MiB"):format(bytes / 1048576) end
  return ("%d KiB"):format(math.floor(bytes / 1024))
end

local function uptime()
  local s = math.floor(computer.uptime())
  local d, h, m = math.floor(s / 86400), math.floor(s / 3600) % 24, math.floor(s / 60) % 60
  local parts = {}
  if d > 0 then parts[#parts + 1] = d .. "d" end
  if h > 0 then parts[#parts + 1] = h .. "h" end
  if m > 0 then parts[#parts + 1] = m .. "m" end
  if #parts == 0 then parts[1] = (s % 60) .. "s" end
  return table.concat(parts, " ")
end

local pkgs = 0
for _ in ipairs(k.fs.list("/var/lib/pacman/local") or {}) do pkgs = pkgs + 1 end

local tier = ({ [1] = 1, [4] = 2, [8] = 3 })[term.depth] or "?"
local total, free = computer.totalMemory(), computer.freeMemory()
local used = total - free

local disk
do
  local p = k.fs.resolve("/")
  if p and p.spaceTotal then
    local ok, t = pcall(p.spaceTotal)
    local ok2, u = pcall(p.spaceUsed)
    if ok and ok2 and t and t > 0 then
      disk = ("%s / %s (%d%%)"):format(human(u), human(t), math.floor(100 * u / t + 0.5))
    end
  end
end

local user, host = _G.USER or "root", _G.HOSTNAME or "byteos"
local info = {
  { nil, user .. "@" .. host },
  { nil, string.rep("-", term.ulen(user .. "@" .. host)) },
  { "OS",       (_G._OSVERSION or "ByteOS") .. " (" .. (_G._OSCODENAME or "") .. ")" },
  { "Host",     "OpenComputers " .. computer.address():sub(1, 8) },
  { "Kernel",   "bytekernel " .. ((_G._OSVERSION or ""):match("[%d%.]+") or "?") },
  { "Uptime",   uptime() },
  { "Packages", pkgs .. " (pacman)" },
  { "Shell",    "byteshell" },
  { "Display",  ("%dx%d, %d-bit"):format(W, H, term.depth) },
  { "GPU",      "Tier " .. tier },
  { "CPU",      (_VERSION or "Lua") .. " VM" },
  { "Memory",   ("%s / %s (%d%%)"):format(human(used), human(total), math.floor(100 * used / total + 0.5)) },
}
if disk then info[#info + 1] = { "Disk (/)", disk } end
-- colour swatches, when there are colours and room to show them
if not T.mono and #info + 3 <= H - 2 then
  info[#info + 1] = { nil, "" }
  info[#info + 1] = { "swatch", 1 }
  info[#info + 1] = { "swatch", 2 }
end

-- ---- layout ----------------------------------------------------------------
local labelW = 0
for _, row in ipairs(info) do
  if row[1] and row[1] ~= "swatch" then labelW = math.max(labelW, #row[1]) end
end
local infoW = 0
for _, row in ipairs(info) do
  if row[1] ~= "swatch" then infoW = math.max(infoW, (row[1] and labelW + 2 or 0) + term.ulen(row[2])) end
end

local function width(t) local w = 0 for _, l in ipairs(t) do w = math.max(w, term.ulen(l)) end return w end
local logo = BIG
if width(BIG) + 3 + math.min(infoW, 34) > W or #BIG > H - 3 then logo = SMALL end
if width(logo) + 3 + 20 > W then logo = {} end   -- very narrow: info only
local logoW = #logo > 0 and width(logo) + 3 or 0
local room = W - logoW - 1

local swatches = {
  { T.bg, T.red, T.green, T.yellow, T.accent, T.magenta, T.cyan, T.fg },
  { T.dim, T.orange, T.ok, T.warn, T.blue, T.magenta, T.cyan, T.bright },
}

-- Logo and info are vertically centred against each other.
local rows = math.max(#logo, #info)
local logoTop = math.floor((rows - #logo) / 2)
local infoTop = math.floor((rows - #info) / 2)

if H >= 20 then term.write("\n") end
for i = 1, rows do
  local l = logo[i - logoTop]
  if logoW > 0 then
    term.cwrite(T.accent, term.pad(l or "", logoW))
  end
  local row = info[i - infoTop]
  if row then
    local label, value = row[1], row[2]
    if label == "swatch" then
      local n = math.min(#swatches[value], math.floor(room / 3))
      for j = 1, n do term.cwrite(swatches[value][j], "███") end
    elseif label then
      term.cwrite(T.accent, term.pad(label, labelW))
      term.cwrite(T.muted, ": ")
      local fit = math.max(0, room - labelW - 2)
      -- drop a trailing "(..)" detail rather than cutting the value mid-way
      if term.ulen(value) > fit then value = value:gsub("%s*%b()$", "") end
      term.cwrite(T.fg, term.usub(value, 1, fit))
    elseif i - infoTop == 1 then
      local at = value:find("@", 1, true)
      term.cwrite(T.accent, value:sub(1, at - 1))
      term.cwrite(T.fg, "@")
      term.cwrite(T.accent, value:sub(at + 1))
    else
      term.cwrite(T.muted, term.usub(value, 1, room))
    end
  end
  term.write("\n")
end
return 0
