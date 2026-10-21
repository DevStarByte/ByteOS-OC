--[[
  printf FORMAT [ARG...]   print ARGs as FORMAT describes

    %s text   %d %i whole number   %f decimal number   %x %X hex
    %o octal  %c the first character   %% a %
    widths and precision as in C: %5s  %-10s  %05d  %.2f
    escapes: \n new line  \t tab  \\ backslash  \e escape  \0NNN octal byte

  Unlike echo, printf adds no new line by itself. With more ARGs than
  the format uses, the format is used again for the rest:

    printf '%s=%d\n' a 1 b 2         a=1  b=2 on two lines
]]--
local args = arg or {}
if not args[1] then term.write("usage: printf FORMAT [ARG...]\n"); return 1 end

local ESC = { n = "\n", t = "\t", r = "\r", a = "\a", b = "\b", f = "\f", v = "\v", e = "\27", ["\\"] = "\\", ['"'] = '"' }
local function escapes(s)
  return (s:gsub("\\0([0-7]?[0-7]?[0-7]?)", function(oct)
    return string.char(oct == "" and 0 or tonumber(oct, 8) & 255)
  end):gsub("\\(.)", function(c) return ESC[c] or ("\\" .. c) end))
end

local format = escapes(args[1])
local rest, n = {}, 0
for i = 2, #args do rest[#rest + 1] = args[i] end
local rc = 0
local function nextArg()
  n = n + 1
  return rest[n]
end
local function number(v, conv)
  if v == nil or v == "" then return 0 end
  local x = tonumber(v)
  if not x and v:match("^['\"].") then x = utf8.codepoint(v, 2) end -- 'A is 65
  if not x then term.write("printf: '" .. v .. "': expected a number\n"); rc = 1; return 0 end
  if conv ~= "f" and conv ~= "e" and conv ~= "g" then x = math.tointeger(x) or math.floor(x) end
  return x
end

local out = {}
repeat
  local used = n
  local text = format:gsub("%%([-+ #0]*%d*%.?%d*)([diouxXfeEgGsc%%])", function(flags, conv)
    if conv == "%" then return "%" end
    local v = nextArg()
    if conv == "s" then return ("%" .. flags .. "s"):format(v or "") end
    if conv == "c" then return ("%" .. flags .. "s"):format((v or ""):match("^[%z\1-\127\194-\244][\128-\191]*") or "") end
    if conv == "i" or conv == "u" then conv = "d" end
    return ("%" .. flags .. conv):format(number(v, conv))
  end)
  out[#out + 1] = text
until n >= #rest or n == used
term.write(table.concat(out))
return rc
