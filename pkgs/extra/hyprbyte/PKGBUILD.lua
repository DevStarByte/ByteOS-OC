return {
  name    = "hyprbyte",
  version = "1.0.0",
  rel     = 1,
  desc    = "tiling window manager in the spirit of Hyprland: windows, workspaces, a bar",
  depends = { "byteos>=1.13.0" },
  backup  = { "/etc/hyprbyte.conf" },
}
