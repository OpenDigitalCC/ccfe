# CCFE developer tasks.  Standard Debian packages only:
#   perl libcurses-perl libperl-critic-perl perltidy
#
#   make test        run the test suite
#   make critic      Perl::Critic: modules (sev 3) + ccfe.pl (sev 5, legacy)
#   make tidy        reformat the modules and ccfe.pl in place (keeps .bak)
#   make tidy-check  fail if the modules or ccfe.pl are not tidy
#   make check       test + critic + tidy-check (what CI runs)

SRC = src

# Everything held to the perltidy house style: the modules and the main script.
TIDY_FILES = $(SRC)/lib/CCFE/*.pm $(SRC)/ccfe.pl

.PHONY: test critic tidy tidy-check check

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
