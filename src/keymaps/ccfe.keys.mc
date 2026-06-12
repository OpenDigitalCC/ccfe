# CCFE keymap preset: "mc"
#
# A Midnight Commander flavoured layout (F1 Help, F3 View, F4 Edit, F10 Quit),
# mapped onto CCFE's functions, each with a Meta alternate so it survives a
# terminal that grabs the high F-keys.  See ccfe.conf(5).

keymap {
  help         = F1, M-h
  list         = F2, M-l
  show_action  = F3, M-a
  save         = F4, M-w
  sel_items    = F5, M-s
  redraw       = F6, M-r
  shell_escape = F9, M-x
  back         = F8, M-b
  exit         = F10, M-q
}
