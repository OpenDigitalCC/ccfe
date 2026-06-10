# CCFE developer tasks.  Standard Debian packages only:
#   perl libcurses-perl libperl-critic-perl perltidy
#
#   make test        run the test suite
#   make critic      Perl::Critic on the new modules
#   make tidy        reformat the new modules in place (keeps .bak)
#   make tidy-check  fail if the new modules are not tidy
#   make check       test + critic + tidy-check (what CI runs)

SRC = src

.PHONY: test critic tidy tidy-check check

test:
	cd $(SRC) && prove -lr t/

critic:
	perlcritic --profile .perlcriticrc $(SRC)/lib

tidy:
	perltidy --profile=.perltidyrc -b $(SRC)/lib/CCFE/*.pm

tidy-check:
	@status=0; \
	for f in $$(find $(SRC)/lib -name '*.pm'); do \
	  perltidy --profile=.perltidyrc -st $$f 2>/dev/null | diff -q - $$f >/dev/null \
	    || { echo "Not tidy: $$f (run: make tidy)"; status=1; }; \
	done; \
	exit $$status

check: test critic tidy-check
