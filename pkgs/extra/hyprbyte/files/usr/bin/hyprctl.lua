--[[
  hyprctl - control Hyprbyte from one of its windows

    hyprctl clients                 every window: id, workspace, title, pid
    hyprctl workspaces              the workspaces and how many windows each has
    hyprctl activewindow            the window in focus
    hyprctl version
    hyprctl dispatch <what> [arg]   do something, as a key would:
        exec <command>              open a window running it
        workspace <n>               go to workspace n
        movetoworkspace <n>         send the window in focus there
        killactive                  close the window in focus
        fullscreen                  full screen on / off
        cyclenext                   focus the next window
        exit                        quit Hyprbyte
]]--
local state = package.loaded["hyprbyte.state"]
local args = arg or {}
local T = term.theme
if not state then term.write("hyprctl: Hyprbyte is not running\n"); return 1 end
local cmd = args[1] or "clients"

local function each(fn)
  for n, space in ipairs(state.workspaces) do
    for i, win in ipairs(space.list) do fn(n, i, win, space) end
  end
end

if cmd == "clients" then
  each(function(n, i, win, space)
    term.cwrite(T.accent, ("Window %d"):format(win.id))
    term.write((" -> %s\n  workspace: %d\n  pid: %s\n  focused: %s\n"):format(win.term.title or win.title, n, tostring(win.pid),
      tostring(n == state.active and i == space.focus)))
  end)
elseif cmd == "activewindow" then
  local space = state.workspaces[state.active]
  local win = space.list[space.focus]
  if not win then term.write("no window in focus\n"); return 1 end
  term.write(("Window %d -> %s (workspace %d, pid %s)\n"):format(win.id, win.term.title or win.title, state.active, tostring(win.pid)))
elseif cmd == "workspaces" then
  for n, space in ipairs(state.workspaces) do
    if #space.list > 0 or n == state.active then
      term.write(("workspace %d%s: %d window%s\n"):format(n, n == state.active and " (active)" or "",
        #space.list, #space.list == 1 and "" or "s"))
    end
  end
elseif cmd == "version" then
  term.write("Hyprbyte " .. state.version .. "\n")
elseif cmd == "dispatch" then
  local what = args[2]
  if not what or not state.dispatchers[what] then
    term.write("hyprctl: unknown dispatcher " .. tostring(what) .. " (see man hyprctl)\n")
    return 1
  end
  state.queue[#state.queue + 1] = { what, table.concat(args, " ", 3) }
else
  term.write("usage: hyprctl clients | workspaces | activewindow | version | dispatch <what> [arg]\n")
  return 1
end
return 0
