-- Quickshell's default shell. Copy it to ~/.config/quickshell/shell.lua
-- and change it there: Quickshell reloads it as soon as you save.
-- Every widget is described in `man quickshell`.
return {
  PanelWindow {
    anchor = "top",
    color = "base",
    Text { text = " ◆ ", color = "accent" },
    Workspaces {},
    Separator {},
    ActiveWindow { max = 40 },
    Spacer {},
    Memory {},
    Separator {},
    Energy {},
    Separator {},
    Clock { format = "%a %d %b  %H:%M " },
  },
}
