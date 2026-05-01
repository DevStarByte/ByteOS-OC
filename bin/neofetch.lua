-- neofetch-style system info banner for ByteOS
local lines = {
  "                   -`                  ",
  "                  .o+`                 ",
  "                 `ooo/                 ",
  "                `+oooo:                ",
  "               `+oooooo:               ",
  "               -+oooooo+:              ",
  "             `/:-:++oooo+:             ",
  "            `/++++/+++++++:            ",
  "           `/++++++++++++++:           ",
  "          `/+++ooooooooooooo/`         ",
  "         ./ooosssso++osssssso+`        ",
  "        .oossssso-````/ossssss+`       ",
  "       -osssssso.      :ssssssso.      ",
  "      :osssssss/        osssso+++.     ",
  "     /ossssssss/        +ssssooo/-     ",
  "   `/ossssso+/:-        -:/+osssso+-   ",
  "  `+sso+:-`                 `.-/+oso:  ",
  " `++:.                           `-/+/ ",
  " .`                                 `/ ",
}

local info = {
  "OS:       " .. (_G._OSVERSION or "ByteOS"),
  "Host:     " .. (_G.HOSTNAME or "byteos"),
  "Kernel:   bytekernel-1.0",
  "Uptime:   " .. string.format("%.0f s", computer.uptime()),
  "Shell:    byteshell",
  "CPU:      OpenComputers Lua " .. (_VERSION or ""),
  "Memory:   " .. math.floor((computer.totalMemory() - computer.freeMemory()) / 1024) ..
              " / " .. math.floor(computer.totalMemory() / 1024) .. " KiB",
  "Packages: see /var/lib/pacman/local",
  "User:     " .. (_G.USER or "root"),
}

term.setForeground(0x55AAFF)
local n = math.max(#lines, #info)
for i = 1, n do
  term.write((lines[i] or string.rep(" ", 40)))
  term.setForeground(0xFFFFFF)
  term.write("  " .. (info[i] or "") .. "\n")
  term.setForeground(0x55AAFF)
end
term.setForeground(0xFFFFFF)
return 0
