# Changelog

From v1.60 onward, CCFE's changelog **is the git history** — releases are
tagged and every change is a reviewable commit. There is no separately
maintained changelog file to drift out of date.

To see what changed:

```sh
git log --oneline                 # all changes
git log v1.60..HEAD               # since a release
git tag                           # released versions
git show <tag>                    # a specific release
```

For a release summary, generate notes from the tags, e.g.:

```sh
git log --no-merges --pretty='- %s' <previous-tag>..<tag>
```

The original hand-maintained changelog for the pre-git releases
(v1.0 – v1.58, 2009–2016) is preserved at [`src/ChangeLog`](src/ChangeLog).
