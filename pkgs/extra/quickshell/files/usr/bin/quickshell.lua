--[[
  quickshell [-p <file>] - your own desktop shell for Hyprbyte

  Draws the panels described in ~/.config/quickshell/shell.lua (else
  /etc/xdg/quickshell/shell.lua) along the edges of Hyprbyte's screen,
  and draws them again when you save the file. A mistake in it shows up
  in a red panel instead.

  Start it with Hyprbyte: put  exec-once = quickshell  into
  ~/.config/hyprbyte.conf. qs is the same command. See man quickshell.

    -p <file>   use this shell file
]]--
local qs = require("quickshell")
local args = arg or {}
local path
for i = 1, #args do if args[i] == "-p" or args[i] == "--path" then path = args[i + 1] end end
if not path then
  local own = (_G.HOME or "/") .. "/.config/quickshell/shell.lua"
  path = fs.exists(own) and own or "/etc/xdg/quickshell/shell.lua"
end

local hypr = package.loaded["hyprbyte.state"]
if not hypr or not hypr.addLayer then
  print("quickshell: Hyprbyte (1.1 or newer) is not running; start it from Hyprbyte with exec-once = quickshell")
  return 1
end
for _, l in ipairs(hypr.layers) do
  if l.namespace == "quickshell" then print("quickshell: already running"); return 1 end
end

local ctx = { hypr = hypr }
local layers, commands, source = {}, {}, nil

local function show(panels)
  for _, l in ipairs(layers) do hypr.removeLayer(l) end
  layers, commands = {}, {}
  for _, p in ipairs(panels) do
    layers[#layers + 1] = hypr.addLayer({
      namespace = "quickshell", anchor = p.props.anchor or "top", height = p.props.height or 1,
      draw = function(gpu, x, y, w, h) qs.draw(p, ctx, gpu, x, y, w, h) end,
      click = function(x) qs.click(p, ctx, x) end,
    })
    for _, c in ipairs(qs.commands(p)) do commands[#commands + 1] = c end
  end
end

local function load()
  source = fs.readAll(path)
  if not source then return nil, "cannot read " .. path end
  local env = qs.env(hypr)
  local chunk, err = _G.load(source, "=" .. path, "t", env)
  if not chunk then return nil, err end
  local ok, result = pcall(chunk)
  if not ok then return nil, result end
  return qs.panels(result)
end

local function reload()
  local panels, err = load()
  if not panels then
    print("error in " .. path .. ": " .. tostring(err))
    local env = qs.env(hypr)
    panels = { env.PanelWindow { anchor = "top", color = "red", env.Text { text = "quickshell: " .. tostring(err), color = "bright" } } }
  else
    print("loaded " .. path)
  end
  show(panels)
end

reload()
local nextCheck = computer.uptime() + 2
local okRun, err = pcall(function()
  while package.loaded["hyprbyte.state"] == hypr do
    local now = computer.uptime()
    for _, c in ipairs(commands) do
      if now >= (c.due or 0) then
        local buf = {}
        pcall(shell.withIO, { output = buf }, shell.execute, tostring(c.props.cmd or ""))
        c.output = (table.concat(buf):match("^[^\n]*") or "")
        c.due = now + (tonumber(c.props.interval) or 10)
      end
    end
    if now >= nextCheck then
      nextCheck = now + 2
      if fs.readAll(path) ~= source then reload() end
    end
    k.event.pull(0.5)
  end
end)
for _, l in ipairs(layers) do hypr.removeLayer(l) end
if not okRun then error(err, 0) end
return 0
