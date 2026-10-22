--[[
  /usr/lib/json.lua - JSON for Lua scripts and the lua prompt

    local json = require("json")
    json.decode(text)          -> value | nil, "error at position N: why"
    json.encode(value [, opts]) -> text | nil, why
        opts.pretty = true     one value per line, indented by two spaces
        opts.indent = "    "   pretty, with this indentation

  Objects become tables with string keys, arrays tables 1..n, null the
  sentinel json.null (so it can stand in a table). Encoding sorts object
  keys, so the same table always gives the same text. A table whose keys
  are exactly 1..n is an array (an empty table is []; json.object() makes
  an empty {}). Functions, cycles, NaN and infinity cannot be encoded.

  At the lua prompt, or in a script:

    > json = require("json")
    > json.encode({ name = "alice", tags = { "a", "b" } })
    {"name":"alice","tags":["a","b"]}
    > json.decode(fs.readAll("/tmp/answer.json")).name

  An answer from a web API: wget -O /tmp/a.json URL, then decode the file.
]]--

local json = {}

json.null = setmetatable({}, { __tostring = function() return "null" end, __name = "json.null" })
local OBJECT = setmetatable({}, { __mode = "k" })  -- tables to encode as {} even when empty

-- An empty table that encodes as {} instead of [].
function json.object(t)
  t = t or {}
  OBJECT[t] = true
  return t
end

-- ---- decoding -------------------------------------------------------------------
local ESCAPES = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }

local function utf8char(cp)
  if utf8 and utf8.char then return utf8.char(cp) end
  if cp < 0x80 then return string.char(cp) end
  if cp < 0x800 then return string.char(0xC0 | (cp >> 6), 0x80 | (cp & 0x3F)) end
  if cp < 0x10000 then return string.char(0xE0 | (cp >> 12), 0x80 | ((cp >> 6) & 0x3F), 0x80 | (cp & 0x3F)) end
  return string.char(0xF0 | (cp >> 18), 0x80 | ((cp >> 12) & 0x3F), 0x80 | ((cp >> 6) & 0x3F), 0x80 | (cp & 0x3F))
end

function json.decode(text)
  if type(text) ~= "string" then return nil, "error at position 1: not a string" end
  local pos = 1
  local function fail(why) error({ json = ("error at position %d: %s"):format(pos, why) }, 0) end
  local function skip()
    pos = text:find("[^ \t\r\n]", pos) or #text + 1
  end
  local value

  local function str()
    pos = pos + 1 -- the opening quote
    local parts = {}
    while true do
      local s, e = text:find('["\\%c]', pos)
      if not s then fail("unterminated string") end
      parts[#parts + 1] = text:sub(pos, s - 1)
      local c = text:sub(s, s)
      if c == '"' then pos = s + 1; break end
      if c ~= "\\" then pos = s; fail("control character in a string") end
      local esc = text:sub(s + 1, s + 1)
      if ESCAPES[esc] then
        parts[#parts + 1] = ESCAPES[esc]; pos = s + 2
      elseif esc == "u" then
        local hex = text:match("^%x%x%x%x", s + 2)
        if not hex then pos = s; fail("bad \\u escape") end
        local cp = tonumber(hex, 16)
        pos = s + 6
        if cp >= 0xD800 and cp <= 0xDBFF then
          local lo = text:match("^\\u(%x%x%x%x)", pos)
          lo = lo and tonumber(lo, 16)
          if lo and lo >= 0xDC00 and lo <= 0xDFFF then
            cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00)
            pos = pos + 6
          else
            cp = 0xFFFD -- a lone surrogate
          end
        elseif cp >= 0xDC00 and cp <= 0xDFFF then
          cp = 0xFFFD
        end
        parts[#parts + 1] = utf8char(cp)
      else
        pos = s; fail("bad escape \\" .. esc)
      end
    end
    return table.concat(parts)
  end

  -- -12, 3.5, 1e9, -0.25E-3: integer part, fraction, exponent
  local function num()
    local int = text:match("^-?%d+", pos)
    if not int or int:match("^-?0%d") then fail("bad number") end
    local frac = text:match("^%.%d+", pos + #int)
    if not frac and text:sub(pos + #int, pos + #int) == "." then fail("bad number") end
    frac = frac or ""
    local exp = text:match("^[eE][-+]?%d+", pos + #int + #frac)
    if not exp and text:find("^[eE]", pos + #int + #frac) then fail("bad number") end
    exp = exp or ""
    local s = int .. frac .. exp
    pos = pos + #s
    if frac == "" and exp == "" then return math.tointeger(tonumber(s)) or tonumber(s) end
    return tonumber(s) + 0.0
  end

  local function array()
    pos = pos + 1
    local t, n = {}, 0
    skip()
    if text:sub(pos, pos) == "]" then pos = pos + 1; return t end
    while true do
      n = n + 1
      t[n] = value()
      skip()
      local c = text:sub(pos, pos)
      pos = pos + 1
      if c == "]" then return t end
      if c ~= "," then pos = pos - 1; fail("expected , or ]") end
    end
  end

  local function object()
    pos = pos + 1
    local t = json.object()
    skip()
    if text:sub(pos, pos) == "}" then pos = pos + 1; return t end
    while true do
      skip()
      if text:sub(pos, pos) ~= '"' then fail("expected a key in quotes") end
      local key = str()
      skip()
      if text:sub(pos, pos) ~= ":" then fail("expected :") end
      pos = pos + 1
      t[key] = value()
      skip()
      local c = text:sub(pos, pos)
      pos = pos + 1
      if c == "}" then return t end
      if c ~= "," then pos = pos - 1; fail("expected , or }") end
    end
  end

  value = function()
    skip()
    local c = text:sub(pos, pos)
    if c == "{" then return object()
    elseif c == "[" then return array()
    elseif c == '"' then return str()
    elseif c == "-" or c:match("%d") then return num()
    elseif text:sub(pos, pos + 3) == "true" then pos = pos + 4; return true
    elseif text:sub(pos, pos + 4) == "false" then pos = pos + 5; return false
    elseif text:sub(pos, pos + 3) == "null" then pos = pos + 4; return json.null
    elseif c == "" then fail("unexpected end of the text")
    else fail("unexpected '" .. c .. "'") end
  end

  local ok, res = pcall(function()
    local v = value()
    skip()
    if pos <= #text then fail("text after the value") end
    return v
  end)
  if ok then return res end
  if type(res) == "table" and res.json then return nil, res.json end
  error(res, 0)
end

-- ---- encoding -------------------------------------------------------------------
local function quote(s)
  return '"' .. s:gsub('[%c"\\]', function(c)
    local named = { ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f",
                    ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }
    return named[c] or ("\\u%04x"):format(c:byte())
  end) .. '"'
end

-- 1..n with nothing else: an array
local function isArray(t)
  if OBJECT[t] then return false end
  local n = 0
  for k in pairs(t) do
    if math.type(k) ~= "integer" or k < 1 then return false end
    n = n + 1
  end
  for i = 1, n do if t[i] == nil then return false end end
  return true
end

function json.encode(value, opts)
  opts = opts or {}
  local indent = opts.indent or (opts.pretty and "  ") or nil
  local seen = {}
  local out = {}
  local function put(s) out[#out + 1] = s end

  local function enc(v, depth)
    local t = type(v)
    if v == json.null or v == nil then put("null")
    elseif t == "boolean" then put(tostring(v))
    elseif t == "number" then
      if v ~= v or v == math.huge or v == -math.huge then error("cannot encode " .. tostring(v), 0) end
      if math.type(v) == "integer" then put(tostring(v))
      elseif v == math.floor(v) and math.abs(v) < 2^53 then put(("%d"):format(v))
      else put(("%.14g"):format(v)) end
    elseif t == "string" then put(quote(v))
    elseif t == "table" then
      if seen[v] then error("cannot encode a table that contains itself", 0) end
      seen[v] = true
      local nl = indent and ("\n" .. indent:rep(depth + 1)) or ""
      local close = indent and ("\n" .. indent:rep(depth)) or ""
      if isArray(v) then
        if #v == 0 then put("[]")
        else
          put("[")
          for i = 1, #v do
            if i > 1 then put(",") end
            put(nl); enc(v[i], depth + 1)
          end
          put(close .. "]")
        end
      else
        local keys = {}
        for k in pairs(v) do
          local kt = type(k)
          if kt ~= "string" and kt ~= "number" then error("cannot encode a " .. kt .. " key", 0) end
          keys[#keys + 1] = k
        end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        if #keys == 0 then put("{}")
        else
          put("{")
          for i, k in ipairs(keys) do
            if i > 1 then put(",") end
            put(nl); put(quote(tostring(k))); put(indent and ": " or ":")
            enc(v[k], depth + 1)
          end
          put(close .. "}")
        end
      end
      seen[v] = nil
    else
      error("cannot encode a " .. t, 0)
    end
  end

  local ok, err = pcall(enc, value, 0)
  if not ok then return nil, err end
  return table.concat(out)
end

return json
