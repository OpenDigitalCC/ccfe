# CCFE — The Curses Command Front-end — minimal runtime image.
#
# Depends on stock Debian packages ONLY:
#   * perl            (core modules: POSIX, IPC::Open3, Text::Balanced, ...)
#   * libcurses-perl  (the Curses / ncurses + form + menu bindings)
#
# The previous Dockerfiles built a bespoke GCC 7.5 + binutils + statically
# linked ncurses + a 2020 Perl, on the theory that issue #1 ("segfault on
# forms") needed a static Curses.  It did not: the crash was a Perl logic
# bug (building a curses menu from an empty item list), fixed in v1.60.
# See REFACTOR.md for the analysis.  This image therefore just installs
# the distro packages and runs the program.

FROM debian:stable-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        perl \
        libcurses-perl \
        ncurses-base \
        ncurses-term \
 && rm -rf /var/lib/apt/lists/*

# Build the program from source using the upstream batch installer, which
# templates the install paths into the script and installs the bundled
# sysmon sample plugin into the demo menu.
WORKDIR /opt/ccfe-src
COPY src/ ./
RUN sh install.sh -b -p /usr/local/ccfe

ENV PATH="/usr/local/ccfe/bin:${PATH}"
ENV TERM=xterm

# `docker run -it <image>` opens the demo menu; pass a menu/form name to
# jump straight to it, e.g. `docker run -it <image> sysmon`.
ENTRYPOINT ["ccfe"]
CMD ["demo"]
