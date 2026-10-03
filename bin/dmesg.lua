-- dmesg - the system messages since boot, with seconds since power-on
local T = term.theme
for _, e in ipairs(k.dmesg()) do
  term.cwrite(T.muted, ("[%8.3f] "):format(e.t))
  term.write((e.tag ~= "kernel" and (e.tag .. ": ") or "") .. e.msg .. "\n")
end
return 0
