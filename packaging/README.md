# Packaging CCFE

CCFE is interpreted Perl that resolves its install paths at runtime from the
program's own location (see `MIGRATION.md`). Every package therefore stages a
**self-contained tree under `/usr/lib/ccfe`** using the upstream
`src/install.sh`, and adds a `/usr/bin/ccfe` symlink so it is on `PATH`. No
files are templated, so the same program works regardless of prefix.

Runtime dependencies are only **perl** and the **Curses** module
(`libcurses-perl` / `perl-Curses` / `perl-curses`).

## Debian / Ubuntu  (`debian/`, at the repo root)

Built and tested in this repo:

```sh
make deb                          # build + collect under dist/ (tracked in git)
sudo apt install ./dist/ccfe_<version>_all.deb
```

`make deb` runs `dpkg-buildpackage -b -us -uc` (which writes to the parent dir),
moves the `.deb` / `.buildinfo` / `.changes` into `dist/`, and cleans the
regenerated `debian/` build tree.  The built packages live in `dist/` so a
release carries its artifact.

(`build-essential` is not actually needed — CCFE compiles nothing — so add
`-d` to the `dpkg-buildpackage` line if `dpkg-checkbuilddeps` objects.)

## RHEL / Fedora / clones  (`packaging/rpm/ccfe.spec`)

```sh
rpmbuild -ba packaging/rpm/ccfe.spec   # needs rpm-build + a source tarball
```

## Alpine  (`packaging/alpine/APKBUILD`)

```sh
abuild -r                              # needs alpine-sdk
```

The RPM and Alpine recipes are provided but were **not built in the
development environment** (no `rpmbuild` / `abuild` there); the Debian package
is the verified reference and the other two mirror it exactly.
