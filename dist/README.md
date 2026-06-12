# dist/ — built release packages

Binary packages built from this source tree, tracked in git so a tagged
release carries its artifact.  Produced by `make deb` (which runs
`dpkg-buildpackage` and moves the `.deb` / `.buildinfo` / `.changes` here).

Install a build with, e.g.:

```sh
sudo apt install ./dist/ccfe_2.3_all.deb
```
