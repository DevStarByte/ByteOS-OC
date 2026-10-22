--[[
  play - play tunes on the computer's speaker or on note blocks

    play SONG             a song: a file, or the name of one in
                          /usr/share/play (play ode-to-joy)
    play -n "NOTES"       notes given right here: play -n "C4 E4 G4 C5*2"
    play -l               the songs in /usr/share/play
    -t BPM                another tempo (beats per minute)
    -s                    the speaker even when note blocks are there

  A song is a text file of notes, read left to right:

    # Ode to Joy           a # at the start of a word is a comment
    tempo 120              beats per minute (default 120)
    E4 E4 F4 G4 | G4 F4 E4 D4 | C4 C4 D4 E4 | E4. D4/2 D4*2

  A note is a letter A-G, # or b, and an octave 0-8 (A4 is 440 Hz). It
  lasts one beat; *2 doubles that, /2 halves it, a . adds half again
  (E4. = one and a half beats). R is a rest, | is ignored (bar lines).

  It plays on Computronics iron note blocks or note blocks behind an
  adapter when there are any (all of them at once; notes out of their
  two octaves are moved by octaves into it), else on the computer's own
  speaker (20-2000 Hz). Ctrl+C stops.
]]--
local args = arg or {}
local DIR = "/usr/share/play"

local tempo, notes, file, speakerOnly
local i = 1
while i <= #args do
  local a = args[i]
  if a == "-l" then
    local names = {}
    for _, f in ipairs(fs.list(DIR) or {}) do
      local n = f:match("^(.+)%.txt$")
      if n then names[#names + 1] = n end
    end
    table.sort(names)
    for _, n in ipairs(names) do
      local first = (fs.readAll(DIR .. "/" .. n .. ".txt") or ""):match("^#%s*([^\n]*)")
      term.write(term.pad(n, 16) .. (first or "") .. "\n")
    end
    return 0
  elseif a == "-t" then i = i + 1; tempo = tonumber(args[i])
    if not tempo or tempo <= 0 then term.write("play: -t needs beats per minute\n"); return 2 end
  elseif a == "-n" then i = i + 1; notes = args[i]
  elseif a == "-s" then speakerOnly = true
  elseif a:sub(1, 1) == "-" then term.write("play: unknown option " .. a .. "\n"); return 2
  else file = a end
  i = i + 1
end

local text
if notes then
  text = notes
elseif file then
  local path = shell.normalize(file)
  if not fs.exists(path) and not file:find("/") then
    path = DIR .. "/" .. file:gsub("%.txt$", "") .. ".txt"
  end
  local err
  text, err = fs.readAll(path)
  if not text then term.write("play: " .. file .. ": " .. tostring(err or "no such song") .. "\n"); return 1 end
else
  term.write("usage: play SONG | play -n \"NOTES\" | play -l\n"); return 2
end

-- ---- reading the notes ---------------------------------------------------------
local SEMITONE = { C = 0, D = 2, E = 4, F = 5, G = 7, A = 9, B = 11 }

-- { midi = n or nil for a rest, beats = b }, or nil, why
local function note(word)
  local name, acc, oct, rest = word:match("^([A-Ga-g])([#b]?)(%d)(.*)$")
  local midi
  if name then
    midi = (tonumber(oct) + 1) * 12 + SEMITONE[name:upper()] + (acc == "#" and 1 or acc == "b" and -1 or 0)
  else
    rest = word:match("^[Rr](.*)$")
    if not rest then return nil, "not a note: " .. word end
  end
  local beats = 1
  for op, n in rest:gmatch("([%*/%.])(%d*)") do
    if op == "." then beats = beats * 1.5
    else
      n = tonumber(n)
      if not n or n == 0 then return nil, "not a length: " .. word end
      beats = op == "*" and beats * n or beats / n
    end
  end
  if rest:gsub("[%*/]%d+", ""):gsub("%.", "") ~= "" then return nil, "not a note: " .. word end
  return { midi = midi, beats = beats }
end

-- The notes of a song file, or of -n (where # can only be a sharp, so
-- there are no comments). nil, "where: why" on a mistake.
local function parse(src, comments)
  local list, lineNo = {}, 0
  for line in (src .. "\n"):gmatch("([^\n]*)\n") do
    lineNo = lineNo + 1
    line = line:gsub("\r", "")
    -- a comment's # starts a word; a sharp's follows its letter (C#4)
    if comments then line = line:gsub("^#.*$", ""):gsub("%s#.*$", "") end
    local t = line:match("^%s*tempo%s+(%d+%.?%d*)%s*$")
    if t then
      tempo = tempo or tonumber(t)
    else
      for word in line:gmatch("%S+") do
        if word ~= "|" then
          local n, why = note(word)
          if not n then return nil, (comments and (file .. ", line " .. lineNo .. ": ") or "") .. why end
          list[#list + 1] = n
        end
      end
    end
  end
  return list
end

local song, perr = parse(text, not notes)
if not song then term.write("play: " .. perr .. "\n"); return 1 end
tempo = tempo or 120

-- ---- where it sounds -----------------------------------------------------------
local blocks = {}
if not speakerOnly then
  for addr, kind in component.list() do
    if kind == "iron_noteblock" or kind == "note_block" then
      blocks[#blocks + 1] = { kind = kind, proxy = component.proxy(addr) }
    end
  end
end

local function hz(midi) return 440 * 2 ^ ((midi - 69) / 12) end

-- note blocks span F#3 (0) .. F#5 (24)
local function blockPitch(midi)
  local p = midi - 54
  while p < 0 do p = p + 12 end
  while p > 24 do p = p - 12 end
  return p
end

local warned = false
local function sound(midi, seconds)
  if #blocks > 0 then
    local p = blockPitch(midi)
    for _, b in ipairs(blocks) do
      if b.kind == "iron_noteblock" then pcall(b.proxy.playNote, 0, p)
      else pcall(b.proxy.trigger, p + 1) end -- OpenComputers counts 1-25
    end
    return
  end
  local f = hz(midi)
  if f < 20 or f > 2000 then
    if not warned then term.write("play: notes below 20 Hz or above 2000 Hz are skipped\n"); warned = true end
    return
  end
  computer.beep(f, math.min(seconds, 5))
end

-- ---- playing -------------------------------------------------------------------
local beat = 60 / tempo
for _, n in ipairs(song) do
  local seconds = n.beats * beat
  local start = computer.uptime()
  -- the speaker plays a little shorter, so repeated notes stay apart
  if n.midi then sound(n.midi, seconds * 0.9) end
  -- the speaker may or may not wait by itself: wait for what is left,
  -- also when a key or a network message ends the wait early
  local deadline = start + seconds
  while computer.uptime() < deadline do k.event.pull(deadline - computer.uptime()) end
end
return 0
