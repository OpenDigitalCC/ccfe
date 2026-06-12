# CCFE — OpenWrt package

`Makefile` is an OpenWrt package recipe for CCFE (FEATURE-REQUESTS **E1**).

CCFE is a Perl program plus declarative data files, so the package compiles
nothing — the bundled installer stages the same self-contained tree the `.deb`
and `.rpm` ship (under `/usr/lib/ccfe`, with a `/usr/bin/ccfe` symlink), and
CCFE resolves its paths at runtime from the binary location.

## Building

This must be built inside an **OpenWrt buildroot or SDK** for your target — it
cannot be built from this repo's `Makefile` (that one builds the `.deb`/`.rpm`).

1. Copy this directory into the buildroot as a package, e.g.
   `package/utils/ccfe/`, or add it through a custom feed.
2. Make sure the **`packages`** feed is enabled (it provides `perl`,
   `perlbase-*` and — the porting risk — **`perl-curses`**):
   ```sh
   ./scripts/feeds update -a && ./scripts/feeds install -a
   ```
3. Select `Utilities → ccfe` in `make menuconfig`, then:
   ```sh
   make package/ccfe/compile V=s
   ```
   The `.ipk` lands under `bin/packages/<arch>/…`.

## Caveats

- **`perl-curses`** is the dependency to verify first: CCFE needs the Curses XS
  binding and will not start without it. If your feed lacks it, build/add it.
- The `perlbase-*` dependency list in the `Makefile` covers the core modules
  CCFE uses; the exact split-package names drift a little between OpenWrt
  releases — adjust if a build reports a missing `perlbase-*`.
- The recipe fetches the tagged release over git with `PKG_MIRROR_HASH:=skip`;
  set a real hash (and point `PKG_SOURCE_URL` at wherever the release is tagged)
  for a production feed.
- Man pages are staged under `/usr/lib/ccfe/man`; trim them in
  `Package/ccfe/install` if image size matters on the target.

## OpenWrt admin menu (future)

The second half of E1 — a curated OpenWrt admin menu/plugin wrapping `uci`,
service control, `opkg`, network/firewall and `logread` (the "remembered
commands" pattern, OpenWrt-flavoured) — is not in this package yet. It pairs
naturally with the kiosk login (`ccfe -R` + `ccfe-login`) for an appliance UI.
