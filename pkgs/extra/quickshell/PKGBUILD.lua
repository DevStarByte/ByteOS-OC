return {
  name    = "quickshell",
  version = "1.0.1",
  rel     = 1,
  desc    = "build your own desktop shell for Hyprbyte: bars and widgets from a Lua file",
  depends = { "hyprbyte>=1.1.0" },
  backup  = { "/etc/xdg/quickshell/shell.lua" },
  install = "quickshell.install",
}
