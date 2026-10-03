--[[
  /lib/starshell.lua  -  StarShell
  ByteShell with a Starship-style segmented prompt:

     user > host > ~/projects >
    > _

  Everything else (syntax highlighting, grey autosuggestions, history,
  Tab completion, aliases) is ByteShell's own; see /lib/shell.lua and
  /lib/lineedit.lua. `exit` returns to ByteShell, `logout` logs out.
]]--

local term  = require("term")
local shell = require("shell")

local star = {}

-- ---- Colours -----------------------------------------------------------
-- Mapped onto the shared theme (lib/theme.lua) so they fit the GPU palette.
local T = term.theme
local C = {
  fg       = T.fg,
  dim      = T.dim,
  cmd_ok   = T.green,
  flag     = T.yellow,
  -- prompt segments (fg / bg pairs)
  seg_user_bg  = T.accent,  seg_user_fg  = T.on_accent,
  seg_host_bg  = T.raised,  seg_host_fg  = T.bright,
  seg_dir_bg   = T.surface, seg_dir_fg   = T.yellow,
  seg_arrow_ok  = T.green,
  seg_arrow_bad = T.red,
}

local function shorten(path)
  local home = _G.HOME
  if home and path:sub(1, #home) == home then
    path = "~" .. path:sub(#home + 1)
  end
  return path
end

-- ---- Prompt rendering --------------------------------------------------
-- Segmented "starship"-ish prompt; the second line's arrow is green after
-- a successful command and red after a failed one.
local function drawPrompt()
  local user = _G.USER or "root"
  local host = _G.HOSTNAME or "byteos"
  local pwd  = shorten(_G.PWD or "/")

  -- ASCII separators: OC's default font has no powerline glyphs.
  local function seg(text, fg, bg, nextBg)
    term.setBackground(bg); term.setForeground(fg)
    term.write(" " .. text .. " ")
    term.setBackground(nextBg or T.bg); term.setForeground(bg)
    term.write(">")
  end

  if term.getCursor() > 1 then term.write("\n") end
  seg(user, C.seg_user_fg, C.seg_user_bg, C.seg_host_bg)
  seg(host, C.seg_host_fg, C.seg_host_bg, C.seg_dir_bg)
  seg(pwd,  C.seg_dir_fg,  C.seg_dir_bg,  nil)
  term.setBackground(T.bg); term.setForeground(C.fg)
  term.write("\n")

  term.setForeground(shell.status == 0 and C.seg_arrow_ok or C.seg_arrow_bad)
  term.write(user == "root" and "# " or "> ")
  term.setForeground(C.fg)
end

local function welcome()
  term.setForeground(C.cmd_ok)
  term.write("Welcome to StarShell")
  term.setForeground(C.dim); term.write(" - the friendly shell\n")
  term.setForeground(C.fg)
  term.write("Type "); term.setForeground(C.flag); term.write("help")
  term.setForeground(C.fg); term.write(" for help, ")
  term.setForeground(C.flag); term.write("exit"); term.setForeground(C.fg)
  term.write(" to leave.\n\n")
end

-- ---- REPL --------------------------------------------------------------
function star.repl()
  welcome()
  shell.loop(drawPrompt, true)
end

return star
