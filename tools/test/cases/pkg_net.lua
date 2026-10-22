-- lua-json, pastebin and gitget (core): JSON for scripts, and programs
-- from the internet, against a fake internet card.
users()
local P = dofile(REPO .. "/tools/test/pkgrepo.lua")
if not P then return end

test("lua-json, pastebin and gitget install", function()
  lacks(run(P .. "-S lua-json pastebin gitget"), "error")
  ok(file("/usr/lib/json.lua") and file("/usr/bin/pastebin.lua") and file("/usr/bin/gitget.lua"), "their files")
  ok(file("/var/lib/pacman/local/lua-json/desc"), "gitget pulled in lua-json")
end)

-- ---- lua-json --------------------------------------------------------------------
test("json.decode: values, nesting, escapes, unicode, numbers", function()
  package.loaded.json = nil
  local json = require("json")
  local v = json.decode(' { "name": "alice", "n": 3, "list": [1, 2.5, -0.5e2, true, false, null], "o": {} } ')
  eq(v.name, "alice"); eq(v.n, 3); eq(math.type(v.n), "integer")
  eq(v.list[2], 2.5); eq(v.list[3], -50.0); eq(math.type(v.list[3]), "float")
  eq(v.list[4], true); eq(v.list[5], false); eq(v.list[6], json.null)
  eq(next(v.o), nil)
  eq(json.decode('"a\\"b\\\\c\\/d\\n\\t\\b\\f\\r"'), 'a"b\\c/d\n\t\b\f\r')
  eq(json.decode('"\\u00e9\\u20ac"'), "é€")
  eq(json.decode('"\\ud83d\\ude00"'), "😀", "a surrogate pair is one character")
  eq(json.decode('"\\ud83d x"'), "\239\191\189 x", "a lone surrogate becomes U+FFFD")
  eq(json.decode('"ünïcødé"'), "ünïcødé", "UTF-8 passes through")
  eq(json.decode("[]")[1], nil); eq(json.decode("0"), 0); eq(json.decode("-0.0"), -0.0)
  eq(json.decode("1E3"), 1000.0); eq(json.decode("12345678901"), 12345678901)
  eq(#json.decode("[[[[1]]]]")[1][1][1], 1)
end)

test("json.decode: mistakes say where", function()
  local json = require("json")
  local function bad(text, part)
    local v, why = json.decode(text)
    eq(v, nil, text); has(why, part, text)
  end
  bad("{", "error at position 2"); bad("[1,]", "unexpected ']'"); bad('{"a" 1}', "expected :")
  bad('{a:1}', "expected a key in quotes"); bad("01", "bad number"); bad("1.", "bad number")
  bad("1e", "bad number"); bad('"abc', "unterminated string"); bad('"\\x"', "bad escape \\x")
  bad('"\\u12"', "bad \\u escape"); bad("[1] 2", "text after the value"); bad("nul", "unexpected 'n'")
  bad("", "unexpected end"); bad('"a\nb"', "control character")
  local v, why = json.decode(42)
  eq(v, nil); has(why, "not a string")
end)

test("json.encode: compact and pretty, sorted keys, escapes, round trips", function()
  local json = require("json")
  eq(json.encode({ name = "alice", tags = { "a", "b" }, n = 3, ok = true, none = json.null }),
    '{"n":3,"name":"alice","none":null,"ok":true,"tags":["a","b"]}')
  eq(json.encode({}), "[]"); eq(json.encode(json.object()), "{}")
  eq(json.encode({ [1] = "x", [3] = "z" }), '{"1":"x","3":"z"}', "a gap makes an object")
  eq(json.encode('q"\\\n\1é'), '"q\\"\\\\\\n\\u0001é"')
  eq(json.encode(1.5), "1.5"); eq(json.encode(2.0), "2"); eq(json.encode(-7), "-7")
  eq(json.encode({ a = { 1, { b = 2 } }, c = {} }, { pretty = true }),
    '{\n  "a": [\n    1,\n    {\n      "b": 2\n    }\n  ],\n  "c": []\n}')
  eq(json.encode({ 1 }, { indent = "\t" }), "[\n\t1\n]")
  local doc = '{"a":[1,2.5,"x\\u0001y",{"b":null,"c":{}}],"d":"😀","e":false}'
  eq(json.encode(json.decode(doc)), doc, "decode then encode gives the text back")
  local cyc = {}; cyc.self = cyc
  local v, why = json.encode(cyc); eq(v, nil); has(why, "contains itself")
  v, why = json.encode({ f = print }); eq(v, nil); has(why, "cannot encode a function")
  v, why = json.encode(0 / 0); eq(v, nil); has(why, "cannot encode")
  v, why = json.encode({ [true] = 1 }); eq(v, nil); has(why, "boolean key")
end)

test("json from the lua command", function()
  eq(run([[lua -e 'print(require("json").encode({ 1, 2 }))']]), "[1,2]\n")
end)

-- ---- pastebin --------------------------------------------------------------------
test("pastebin get and run", function()
  internetCard({
    ["https://pastebin.com/raw/x8Kq2Rt4"] = 'print("hello from pastebin " .. tostring(...))\n',
  })
  local out, rc = run("pastebin get x8Kq2Rt4 /tmp/hello.lua")
  eq(rc, 0, out); has(out, "Saved /tmp/hello.lua")
  eq(file("/tmp/hello.lua"), 'print("hello from pastebin " .. tostring(...))\n')
  local o2, rc2 = run("pastebin get https://pastebin.com/x8Kq2Rt4 /tmp/hello.lua")
  eq(rc2, 1); has(o2, "exists (-f overwrites it)")
  eq(select(2, run("pastebin get -f pastebin.com/raw/x8Kq2Rt4 /tmp/hello.lua")), 0, "a whole address works too")
  eq(run("pastebin run x8Kq2Rt4 world"), "hello from pastebin world\n")
  local o3, rc3 = run("pastebin get nope1234 /tmp/nope.lua")
  eq(rc3, 1); has(o3, "no paste nope1234")
  has(run("pastebin get http://example.com/abc /tmp/x"), "usage: pastebin")
  undisk("inet0000-test")
end)

local function poster(answer)
  local posted = {}
  plug("internet", "inet-post", { request = function(url, data, headers)
    posted.url, posted.data, posted.headers = url, data, headers
    local given = false
    return {
      finishConnect = function() return true end,
      response = function() return 200, "OK", {} end,
      read = function() if given then return nil end given = true; return answer end,
      close = function() end,
    }
  end })
  return posted
end

test("pastebin put needs a key, then uploads", function()
  put("/tmp/share.lua", "print('a & b = c')\n")
  local posted = poster("https://pastebin.com/AbCd1234\n")
  local out, rc = run("pastebin put /tmp/share.lua")
  eq(rc, 1); has(out, "needs your pastebin developer key"); has(out, "pastebin.com/doc_api")
  eq(posted.url, nil, "nothing was sent without a key")
  ok(file("/etc/pastebin.conf"):find("# key = YOUR_DEVELOPER_KEY", 1, true), "the shipped config has the key commented out")
  put("/etc/pastebin.conf", "# my key\nkey = s3cr3t\n")
  out, rc = run("pastebin put /tmp/share.lua")
  undisk("inet-post")
  eq(rc, 0, out)
  has(out, "Uploaded as https://pastebin.com/AbCd1234"); has(out, "pastebin get AbCd1234 share.lua")
  eq(posted.url, "https://pastebin.com/api/api_post.php")
  has(posted.data, "api_option=paste"); has(posted.data, "api_dev_key=s3cr3t")
  has(posted.data, "api_paste_name=share.lua"); has(posted.data, "api_paste_code=print%28%27a%20%26%20b%20%3D%20c%27%29%0A")
  eq(posted.headers["Content-Type"], "application/x-www-form-urlencoded")
  poster("Bad API request, invalid api_dev_key")
  out, rc = run("PASTEBIN_KEY=wrong; pastebin put /tmp/share.lua")
  undisk("inet-post")
  eq(rc, 1); has(out, "pastebin said: Bad API request, invalid api_dev_key")
  run("set -e PASTEBIN_KEY")
end)

-- ---- gitget ----------------------------------------------------------------------
local API = "https://api.github.com/repos/alice/tools"
local RAW = "https://raw.githubusercontent.com/alice/tools/"
local TREE = [[{"sha":"x","tree":[
  {"path":"README.md","type":"blob","size":12},
  {"path":"bin","type":"tree"},
  {"path":"bin/hi.lua","type":"blob","size":18},
  {"path":"bin/sub","type":"tree"},
  {"path":"bin/sub/deep file.txt","type":"blob","size":5},
  {"path":"big.dat","type":"blob","size":5000000}
],"truncated":false}]]

test("gitget: a whole repository, a folder, a file, a branch", function()
  local asked = internetCard({
    [API] = '{"name":"tools","default_branch":"main"}',
    [API .. "/git/trees/main?recursive=1"] = TREE,
    [API .. "/git/trees/dev?recursive=1"] = '{"tree":[{"path":"x.lua","type":"blob","size":3}]}',
    [RAW .. "main/README.md"] = "# tools here",
    [RAW .. "main/bin/hi.lua"] = 'print("hi there")\n',
    [RAW .. "main/bin/sub/deep%20file.txt"] = "deep\n",
    [RAW .. "dev/x.lua"] = "x=1",
  })
  run("cd /tmp")
  local out, rc = run("gitget alice/tools")
  eq(rc, 0, out)
  eq(file("/tmp/tools/README.md"), "# tools here"); eq(file("/tmp/tools/bin/hi.lua"), 'print("hi there")\n')
  eq(file("/tmp/tools/bin/sub/deep file.txt"), "deep\n", "names with spaces")
  has(out, "(1/3) README.md"); has(out, "skipped, too big: big.dat (4882 KiB)"); has(out, "3 of 3 files in /tmp/tools")
  ok(not file("/tmp/tools/big.dat"), "the big file was skipped")
  eq(run("gitget alice/tools bin -o /tmp/onlybin") ~= nil, true)
  eq(file("/tmp/onlybin/hi.lua"), 'print("hi there")\n'); eq(file("/tmp/onlybin/sub/deep file.txt"), "deep\n")
  ok(not file("/tmp/onlybin/README.md"), "only the folder")
  run("cd /tmp; mkdir one; cd one; gitget alice/tools bin/hi.lua")
  eq(file("/tmp/one/hi.lua"), 'print("hi there")\n', "a single file lands here")
  has(run("gitget alice/tools bin/hi.lua -o /tmp/one"), "exists, kept (-f overwrites)")
  run("gitget alice/tools@dev -o /tmp/dev")
  eq(file("/tmp/dev/x.lua"), "x=1")
  local n = 0
  for _, u in ipairs(asked) do if u == API then n = n + 1 end end
  eq(n, 4, "with @branch the repository itself is not asked")
  local list = run("gitget -n alice/tools bin")
  has(list, "bin/hi.lua"); has(list, "2 files, 23 B -> /tmp/one/bin")
  local more = run("gitget alice/tools -s 10000 -n")
  has(more, "big.dat"); lacks(more, "skipped")
  has(run("gitget alice/tools nothing/here"), "nothing called nothing/here")
  undisk("inet0000-test")
  run("cd /")
end)

test("gitget: GitHub's refusals and a disk that is too small", function()
  internetCard({ [API] = '{"default_branch":"main"}', [API .. "/git/trees/main?recursive=1"] = TREE })
  local out, rc = run("gitget alice/nosuch")
  eq(rc, 1); has(out, "repository alice/nosuch not found (or it is private)")
  has(run("gitget alice/tools@gone"), "branch gone of alice/tools not found")
  local full = run("gitget alice/tools -s 100000 -o /tmp/full")
  has(full, "only"); has(full, "free on that disk"); has(full, "-f tries anyway")
  ok(not file("/tmp/full/README.md"), "nothing was downloaded")
  undisk("inet0000-test")
  plug("internet", "inet-busy", { request = function()
    return { finishConnect = function() return true end, response = function() return 403, "Forbidden", {} end,
             read = function() return nil end, close = function() end }
  end })
  out, rc = run("gitget alice/tools")
  undisk("inet-busy")
  eq(rc, 1); has(out, "too many questions (60 an hour")
  has(run("gitget nonsense"), "usage: gitget")
  has(run("gitget a/b c d e"), "too many arguments")
end)

test("gitget without lua-json, without an internet card", function()
  has(run("gitget alice/tools"), "no internet card")
  os.remove(ROOT .. "/usr/lib/json.lua")
  package.loaded.json = nil
  has(run("gitget alice/tools"), "needs the lua-json package")
end)
