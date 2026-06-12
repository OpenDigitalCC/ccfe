# CCFE developer tasks.  Standard Debian packages only:
#   perl libcurses-perl libperl-critic-perl perltidy
#
#   make test        run the test suite
#   make critic      Perl::Critic: modules (sev 3) + ccfe.pl (sev 5, legacy)
#   make tidy        reformat the modules and ccfe.pl in place (keeps .bak)
#   make tidy-check  fail if the modules or ccfe.pl are not tidy
#   make check       test + critic + tidy-check (what CI runs)
#   make deb         build the .deb and store it (with .buildinfo/.changes)
#                    under dist/, which is tracked in git

SRC = src

# Everything held to the perltidy house style: the modules and the main script.
TIDY_FILES = $(SRC)/lib/CCFE/*.pm $(SRC)/ccfe.pl

# Package version, read from debian/changelog.
VERSION = $(shell dpkg-parsechangelog -SVersion 2>/dev/null)

.PHONY: test critic tidy tidy-check check deb

test:
	cd $(SRC) && prove -lr t/

critic:
	perlcritic --profile .perlcriticrc $(SRC)/lib
	perlcritic --profile .perlcriticrc-ccfe $(SRC)/ccfe.pl

tidy:
	perltidy --profile=.perltidyrc -b $(TIDY_FILES)

tidy-check:
	@status=0; \
	for f in $$(find $(SRC)/lib -name '*.pm') $(SRC)/ccfe.pl; do \
	  perltidy --profile=.perltidyrc -st $$f 2>/dev/null | diff -q - $$f >/dev/null \
	    || { echo "Not tidy: $$f (run: make tidy)"; status=1; }; \
	done; \
	exit $$status

check: test critic tidy-check

# Build the binary package (unsigned) and collect the artifacts in dist/.
# dpkg-buildpackage writes to the parent dir; we move them in and then clean
# the regenerated debian/ build tree.
deb:
	dpkg-buildpackage -b -us -uc
	mkdir -p dist
	mv ../ccfe_$(VERSION)_*.deb ../ccfe_$(VERSION)_*.buildinfo \
	   ../ccfe_$(VERSION)_*.changes dist/
	rm -rf debian/ccfe debian/.debhelper debian/debhelper-build-stamp \
	       debian/files debian/*.substvars debian/*.debhelper.log
	@echo "Packages in dist/:" && ls dist/ccfe_$(VERSION)_*
