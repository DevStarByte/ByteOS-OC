-- ByteNet: the commands against simulated computers, and netd answering.
users()
local BOX2 = "b0x20000-0000-0000-0000-000000000002"
local files = {}
local sent = network({
  [BOX2] = { distance = 12, reply = function(kind, id, ...)
    local a = table.pack(...)
    if kind == "who" then return "who-reply", "box2", "ByteOS 1.11.1" end
    if kind == "ping" then return "ping-reply" end
    if kind == "msg" then files.msg = a[2]; return "msg-reply", true end
    if kind == "file-offer" then
      if a[2] > 65536 then return "file-offer-reply", false, "too big" end
      files.name, files.data = a[1], ""; return "file-offer-reply", true
    end
    if kind == "file-chunk" then files.data = files.data .. a[2]; return "file-chunk-reply", a[1] end
    if kind == "file-done" then return "file-done-reply", true, "/tmp/incoming/root@byteos-" .. files.name end
  end },
})

test("ip shows the card", function()
  local out = run("ip")
  has(out, "card modem000"); has(out, "wired"); has(out, "hostname byteos")
end)

test("netscan finds the other computer", function()
  local out = run("netscan")
  has(out, "box2"); has(out, "b0x20000"); has(out, "ByteOS 1.11.1")
end)

test("ping by name", function()
  local out, rc = run("ping -c 2 box2")
  has(out, "reply from box2: seq=1"); has(out, "distance=12"); has(out, "2 sent, 2 answered, 0% lost")
  eq(rc, 0)
  has(run("ping nobody"), "unknown host 'nobody'")
end)

test("msg and netcp", function()
  run("msg box2 hello there")
  eq(files.msg, "hello there")
  put("/tmp/big.txt", string.rep("x", 20000))
  has(run("netcp /tmp/big.txt box2"), "sent; on box2 it is /tmp/incoming/root@byteos-big.txt")
  eq(files.data, string.rep("x", 20000), "arrived complete, in several chunks")
  put("/tmp/huge.txt", string.rep("x", 70000))
  has(run("netcp /tmp/huge.txt box2"), "refused: too big")
end)

test("netd answers pings, who, messages and files", function()
  run("systemctl start netd")
  kernel.event.pull(0.05)
  local function lastSent() return sent[#sent].args end
  incoming(BOX2, 3, "ping", "id1")
  eq(lastSent()[2], "ping-reply"); eq(lastSent()[3], "id1")
  incoming(BOX2, 3, "who", "id2")
  eq(lastSent()[2], "who-reply"); eq(lastSent()[4], "byteos")
  incoming(BOX2, 3, "msg", "id3", "alice@box2", "hi from box2")
  has(screen(), "Message from alice@box2: hi from box2")
  incoming(BOX2, 3, "file-offer", "id4", "../../etc/evil", 5, "alice@box2")
  incoming(BOX2, 3, "file-chunk", "id4", 1, "hello")
  incoming(BOX2, 3, "file-done", "id4")
  eq(lastSent()[2], "file-done-reply"); eq(lastSent()[4], true)
  local path = lastSent()[5]
  ok(path:match("^/tmp/incoming/"), "saved in /tmp/incoming: " .. tostring(path))
  eq(file(path), "hello")
  eq(file("/etc/evil"), nil, "no path tricks")
  has(file("/var/log/messages"), "netd: File from alice@box2")
end)
