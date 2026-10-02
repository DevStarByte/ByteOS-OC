--[[
  /lib/internet.lua - HTTP over the internet card

    local internet = require("internet")
    internet.available()                  -> true if an internet card is installed
    internet.get(url, sink [, headers])   -> true | nil, reason
        streams the body to sink(chunk); only HTTP 200 counts as success
    internet.fetch(url [, headers])       -> body | nil, reason

  (/bin/sysupdate.lua carries its own copy of this so it can still repair a
  system whose /lib is outdated or broken.)
]]--

local internet = {}

local TIMEOUT = 20 -- seconds without progress before giving up

local function card()
  local addr = component.list("internet")()
  return addr and component.proxy(addr)
end

function internet.available()
  return card() ~= nil
end

function internet.get(url, sink, headers)
  local inet = card()
  if not inet then return nil, "no internet card installed" end
  local hdrs = { ["User-Agent"] = "ByteOS" }
  for k_, v in pairs(headers or {}) do hdrs[k_] = v end

  local ok, h, reason = pcall(inet.request, url, nil, hdrs)
  if not ok or not h then return nil, tostring(ok and reason or h) end

  local deadline = computer.uptime() + TIMEOUT
  while true do
    local okc, done, why = pcall(h.finishConnect)
    if not okc or done == nil then h.close(); return nil, tostring(okc and why or done) end
    if done then break end
    if computer.uptime() > deadline then h.close(); return nil, "connection timed out" end
    kernel.event.pull(0.05)
  end

  local code, message
  repeat
    code, message = h.response()
    if not code then
      if computer.uptime() > deadline then h.close(); return nil, "no response" end
      kernel.event.pull(0.05)
    end
  until code
  if code ~= 200 then
    h.close()
    return nil, ("HTTP %d %s"):format(code, message or ""), code
  end

  local idle = computer.uptime()
  while true do
    local okr, chunk, rerr = pcall(h.read, 8192)
    if not okr then h.close(); return nil, tostring(chunk) end
    if chunk == nil then
      h.close()
      if rerr then return nil, tostring(rerr) end
      return true
    end
    if #chunk > 0 then
      sink(chunk)
      idle = computer.uptime()
    elseif computer.uptime() - idle > TIMEOUT then
      h.close(); return nil, "download stalled"
    else
      kernel.event.pull(0.05)
    end
  end
end

function internet.fetch(url, headers)
  local parts = {}
  local ok, e, code = internet.get(url, function(c) parts[#parts + 1] = c end, headers)
  if not ok then return nil, e, code end
  return table.concat(parts)
end

return internet
