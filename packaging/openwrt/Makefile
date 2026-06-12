#
# OpenWrt package for CCFE (FEATURE-REQUESTS E1).
#
# Drop this directory into an OpenWrt buildroot / SDK as a package (e.g.
# package/utils/ccfe, or via a custom feed), then:
#   make package/ccfe/compile V=s
#
# CCFE is a Perl program plus declarative data files -- nothing is compiled.
# The bundled installer stages the same self-contained tree the .deb/.rpm ship
# (under /usr/lib/ccfe, with a /usr/bin/ccfe symlink) and CCFE resolves its
# paths at runtime from the binary location, so nothing is templated into code.
#
# Caveats (see FEATURE-REQUESTS.md, item E1):
#  * perl-curses -- CCFE needs the Curses XS binding.  Confirm `perl-curses` is
#    available in your feeds (the `packages` feed) or build it; without it ccfe
#    will not start.  This is the main porting risk.
#  * The perlbase-* list below covers the core modules CCFE uses; the exact
#    split-package names vary slightly between OpenWrt releases -- adjust if a
#    build reports a missing perlbase-*.
#  * Man pages are staged under /usr/lib/ccfe/man; trim them in Package/install
#    if image size matters on the target.
#
#  Copyright (C) 2026 CCFE contributors.  GPL-2.0-or-later.

include $(TOPDIR)/rules.mk

PKG_NAME:=ccfe
PKG_VERSION:=2.4
PKG_RELEASE:=1

# Fetch the tagged release from git.  Point this at wherever the release is
# tagged and set a real PKG_MIRROR_HASH for production (replace `skip`).
PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/OpusVL/perl-ccfe.git
PKG_SOURCE_VERSION:=v$(PKG_VERSION)
PKG_MIRROR_HASH:=skip

PKG_MAINTAINER:=CCFE maintainers <ccfedevel@gmail.com>
PKG_LICENSE:=GPL-2.0-or-later
PKG_LICENSE_FILES:=src/COPYING

include $(INCLUDE_DIR)/package.mk

define Package/ccfe
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Curses Command Front-end
  URL:=https://github.com/OpusVL/perl-ccfe
  DEPENDS:=+perl +perl-curses \
	+perlbase-posix +perlbase-getopt +perlbase-ipc +perlbase-io \
	+perlbase-file +perlbase-findbin +perlbase-cwd +perlbase-text \
	+perlbase-digest +perlbase-term +perlbase-sys +perlbase-essential
endef

define Package/ccfe/description
  CCFE puts an interactive, screen-oriented front-end on command-line scripts
  and commands, driven by plain declarative menu and form files.  Modelled on
  AIX's SMIT, with optional colour, menu/form search, runtime theme and key-map
  switching, file-based notifications, and a restricted (kiosk) mode well suited
  to an appliance login.
endef

# Pure Perl + data files: nothing to cross-compile, just syntax-check the
# program on the build host.
define Build/Compile
	perl -c $(PKG_BUILD_DIR)/src/ccfe.pl
endef

# Stage the self-contained tree with the upstream installer, then add the
# on-PATH symlink (relative, so it follows the relocatable tree).
define Package/ccfe/install
	cd $(PKG_BUILD_DIR)/src && sh install.sh -b -p $(1)/usr/lib/ccfe
	$(INSTALL_DIR) $(1)/usr/bin
	$(LN) ../lib/ccfe/bin/ccfe $(1)/usr/bin/ccfe
endef

$(eval $(call BuildPackage,ccfe))
