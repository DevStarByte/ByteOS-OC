-- The manual: command pages from program headers, topic pages, man -k.
test("a command's page is the comment at the top of its program", function()
  local out = run("man grep | head -n 3")
  has(out, "grep(1)  /bin/grep.lua")
  has(out, "grep [-i] [-v] [-n] [-c] [-F] pattern [file...]")
  has(run("man ls"), "ls [-a] [-l] [-1] [path...]", "one-line -- headers work too")
end)

test("commands from packages get pages the same way", function()
  put("/usr/bin/hellod.lua", "--[[\n  hellod - says hello\n\n    hellod [n]   n times\n]]--\nreturn 0\n")
  local out = run("man hellod")
  has(out, "hellod - says hello"); has(out, "hellod [n]   n times")
end)

test("topic pages and built-ins", function()
  has(run("man pacman.conf"), "SigLevel = Optional")
  has(run("man systemd.service"), "ExecStart=")
  local cd = run("man cd")
  has(cd, "cd is a ByteShell built-in"); has(cd, "BUILT-IN COMMANDS")
end)

test("man -k searches names and first lines", function()
  local out = run("man -k disk")
  has(out, "df"); has(out, "lsblk")
  local _, rc = run("man -k zzzz")
  eq(rc, 1)
end)

test("a missing page", function()
  local out, rc = run("man nosuchthing")
  has(out, "No manual entry for nosuchthing"); eq(rc, 16)
end)

test("every command has a usable page", function()
  for _, f in ipairs(kernel.fs.list("/bin")) do
    local name = f:match("^(.+)%.lua$")
    if name then
      local out = run("man " .. name)
      ok(#out > #name + 20 and not out:find("No manual entry", 1, true), "page for " .. name .. ": " .. out)
    end
  end
end)
