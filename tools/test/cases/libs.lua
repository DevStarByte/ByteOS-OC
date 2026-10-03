-- Libraries without the shell: package format, hashes, passwords.
local bpk = require("bpk")
local sha256 = require("sha256")
local auth = require("auth")

test("crc32 of the standard check string", function()
  eq(bpk.hex(bpk.crc32("123456789")), "cbf43926")
  eq(bpk.hex(bpk.crc32("6789", bpk.crc32("12345"))), "cbf43926", "chained")
end)

test("version comparison", function()
  local cases = { { "1.0.0-1", "1.0.0-1", 0 }, { "1.0.1-1", "1.0.0-9", 1 }, { "1.10-1", "1.9-1", 1 },
    { "1.0-2", "1.0-1", 1 }, { "1.0", "1.0-3", 0 }, { "1.0.1", "1.0", 1 }, { "1.0a", "1.0b", -1 },
    { "2", "1.99", 1 }, { "0.2.0-1", "1.0.0-1", -1 } }
  for _, c in ipairs(cases) do eq(bpk.vercmp(c[1], c[2]), c[3], c[1] .. " vs " .. c[2]) end
end)

test("archive round trip, binary-safe and compressed", function()
  local big = string.rep("hello world, this compresses nicely. ", 60)
  local bin = ""
  for i = 0, 255 do bin = bin .. string.char(i) end
  local parts = {}
  bpk.write({ write = function(_, s) parts[#parts + 1] = s end }, {
    { name = ".PKGINFO", data = bpk.formatInfo({ name = "t", version = "1-1", depend = { "a>=1" } }) },
    { name = "/usr/bin/big.txt", data = big },
    { name = "/usr/share/bin.dat", data = bin .. "]]" },
  })
  local blob, pos = table.concat(parts), 1
  local function handle() pos = 1; return { read = function(_, n) local s = blob:sub(pos, pos + n - 1); pos = pos + n; return s ~= "" and s or nil end } end
  local pkg = assert(bpk.inspect(handle()))
  eq(pkg.info.depend[1], "a>=1")
  eq(pkg.files["/usr/bin/big.txt"].flag, "z", "big file compressed")
  local r, got = assert(bpk.open(handle())), {}
  while true do
    local n, f, s = r.next()
    if not n then break end
    got[n] = r.read(f, s)
  end
  eq(got["/usr/bin/big.txt"], big)
  eq(got["/usr/share/bin.dat"], bin .. "]]")
end)

test("unsafe paths are refused", function()
  for _, p in ipairs({ "/a/../etc", "a/b", "/a//b", "/a/./b", "/a/" }) do eq(bpk.validPath(p), false, p) end
  eq(bpk.validPath("/usr/bin/x.lua"), true)
end)

test("sha256 test vectors", function()
  eq(sha256.hex(""), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
  eq(sha256.hex("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
  eq(sha256.hex("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"),
     "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
end)

test("sha256 through a data card gives the same digest", function()
  useDatacard(true)
  eq(sha256.hex("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
  useDatacard(false)
end)

test("password hashes", function()
  local h = auth.hash("geheim")
  ok(h:match("^%$sha256%$%d+%$[^$]+%$%x+$"), "format: " .. h)
  eq(auth.check("geheim", h), true)
  eq(auth.check("falsch", h), false)
  ok(auth.hash("a") ~= auth.hash("a"), "salted")
  local okPlain, legacy = auth.check("pw", "pw")
  eq(okPlain, true); eq(legacy, true, "plain text is legacy")
  eq(auth.check("", "!"), false, "locked account")
end)
