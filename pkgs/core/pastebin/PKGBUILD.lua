return {
  name    = "pastebin",
  version = "1.0.0",
  rel     = 1,
  desc    = "get, run and share programs on pastebin.com (pastebin get CODE file)",
  depends = { "byteos>=1.16.0" },
  backup  = { "/etc/pastebin.conf" },
}
