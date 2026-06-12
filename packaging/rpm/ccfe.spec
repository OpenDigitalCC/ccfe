# RPM spec for CCFE (RHEL/Fedora/clones).
#
# Mirrors the Debian package: a self-contained tree under %{_prefix}/lib/ccfe
# staged by the upstream installer, with a symlink on PATH.  CCFE resolves its
# paths at runtime from the binary location, so nothing is templated.
#
# Build (needs rpm-build + perl):
#   rpmbuild -ba packaging/rpm/ccfe.spec   # after placing a source tarball
#
# NOTE: not built/tested in this environment (no rpmbuild available here).

Name:           ccfe
Version:        2.3.1
Release:        1%{?dist}
Summary:        Curses Command Front-end
License:        GPLv2+
URL:            https://github.com/OpusVL/perl-ccfe
Source0:        %{name}-%{version}.tar.gz
BuildArch:      noarch
BuildRequires:  perl
Requires:       perl >= 5.36.0
Requires:       perl-Curses

%description
CCFE puts an interactive, screen-oriented front-end on command-line scripts
and commands: it prompts for the information a command needs, driven by plain
declarative menu and form files. Modelled on AIX's SMIT, it offers optional
colour theming and a restricted mode for constrained logins. It depends only
on Perl and the Curses module.

%prep
%autosetup

%build
perl -c src/ccfe.pl

%install
cd src && sh install.sh -b -p %{buildroot}%{_prefix}/lib/ccfe
mkdir -p %{buildroot}%{_bindir}
ln -sf ../lib/ccfe/bin/ccfe %{buildroot}%{_bindir}/ccfe

%files
%{_prefix}/lib/ccfe
%{_bindir}/ccfe
%license src/COPYING
%doc README.MD

%changelog
* Wed Jun 11 2026 CCFE maintainers <ccfedevel@gmail.com> - 2.2-1
- CCFE 2.2: completes the de-globalisation onto pure CCFE::* modules and an
  explicit $ctx (ccfe.pl now runs under use v5.36, requires Perl >= 5.36);
  warnings routed to the log so they cannot corrupt the TUI; M8 close-out
  audit fixes.

* Wed Jun 11 2026 CCFE maintainers <ccfedevel@gmail.com> - 2.1.1-1
- CCFE 2.1.1: terminal-resize reflow, display-column (wide-char) layout, full
  colour palette + panel theme, opt-in mouse, --dump/--plugins, and an internal
  de-globalisation onto pure CCFE::* modules (requires Perl >= 5.36).

* Tue Jun 10 2026 CCFE maintainers <ccfedevel@gmail.com> - 2.0-1
- CCFE 2.0: reorganised layout, runtime path resolution, restricted mode,
  optional colour with SMIT themes, and the -k linter.
