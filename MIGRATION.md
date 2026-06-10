# Migrating from CCFE 1.x to 2.0

v2.0 reorganises where files live so that each kind of thing has one obvious
home. The `.menu` / `.form` / `.item` file formats are **unchanged** — only
the directories move. A fresh `install.sh` (or a package) lays everything out
correctly; this note is for upgrading an existing 1.x install and for anyone
who keeps personal menus.

## What moved

| Thing | 1.x location | 2.0 location |
|---|---|---|
| Perl program | `<prefix>/bin/ccfe` | unchanged |
| Perl modules | `<prefix>/lib/perl5/CCFE/` | unchanged |
| **System menus & forms** | `<prefix>/lib/ccfe/` | `<prefix>/share/ccfe/objects/ccfe/` |
| **Themes** | (doc samples) | `<prefix>/share/ccfe/themes/` |
| System config | `<prefix>/etc/ccfe.conf` | unchanged |
| **Per-user menus** | `~/.ccfe/<name>/` | `~/.local/share/ccfe/<name>/` (XDG) |
| **Per-user config** | `~/.ccfe/<name>.conf` | `~/.config/ccfe/<name>.conf` (XDG) |

`~/.ccfe/` is still searched as a **fallback**, so existing personal menus keep
working until you move them. `XDG_DATA_HOME` / `XDG_CONFIG_HOME` are honoured
if set.

## Steps

1. **Reinstall** over the same prefix (system menus/forms/themes land in the
   new `share/ccfe/` locations):

   ```sh
   cd src && sh install.sh -b -p "<prefix>"
   ```

2. **Move your personal menus and config** to the XDG dirs (optional — the
   `~/.ccfe/` fallback keeps them working meanwhile):

   ```sh
   mkdir -p ~/.local/share/ccfe ~/.config/ccfe
   mv ~/.ccfe/ccfe        ~/.local/share/ccfe/      # your menu tree(s)
   mv ~/.ccfe/*.conf      ~/.config/ccfe/           # your per-user config
   ```

3. **Plugins:** packaged plugins that discover the menu directory should read
   `OBJ_DIR` from `ccfe -c` (it falls back to the old `LIB_DIR` name for 1.x).
   The bundled `ccfe-plugin-sysmon/install.sh` shows the pattern.

## Compatibility notes

- `ccfe -c` now prints `OBJ_DIR` (menus/forms) and `THEME_DIR` in addition to
  `LIB_DIR`. `LIB_DIR` is retained for older plugin scripts.
- The `CCFE_OBJ_DIR` environment variable overrides the objects directory;
  the old `CCFE_LIB_DIR` is still honoured.
- **Paths are now resolved at runtime** from the program's own location, so
  the installed `ccfe` is byte-identical to the source and the whole install
  is **relocatable** — move the prefix and it still works. A split (FHS-style)
  layout is selected with environment variables:
  `CCFE_PREFIX`, `CCFE_ETC_DIR`, `CCFE_MSG_DIR`, `CCFE_LOG_DIR`,
  `CCFE_OBJ_DIR`, `CCFE_THEME_DIR` (e.g. `CCFE_ETC_DIR=/etc/ccfe`).
- Nothing about the `.menu` / `.form` / `.item` / `.conf` syntax changed.
