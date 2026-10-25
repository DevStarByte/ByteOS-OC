--[[
  hello - a friendly greeting

    hello                  greets you by your user name

  The smallest package there is: a good one to read before making your
  own (man PKGBUILD).
]]--
term.write("Hello from ByteOS! Greetings, " .. (_G.USER or "stranger") .. ".\n")
return 0
