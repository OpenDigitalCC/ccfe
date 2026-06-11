#!/usr/bin/env perl
#
#  CCFE - The Curses Command Front-end
#  Copyright (C) 2009, 2016 Massimo Loschi
#
#  This program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program; if not, write to the Free Software
#  Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
#
#  Author: Massimo Loschi <ccfedevel@gmail.com>
#

use v5.36;    # strict + warnings + modern features (M7 Phase 6 capstone)
# getch() returns an integer keycode for function/arrow keys but a one-character
# string for ordinary keys, and the event loops compare it numerically against
# KEY_* constants ($ch == KEY_UP).  That is the program's idiom throughout, so
# the "argument isn't numeric" notice it would raise for a character key is just
# noise; silence that one category while keeping every other warning.
no warnings 'numeric';
use Curses;
use Sys::Hostname;
use File::Basename;
use POSIX qw(:sys_wait_h);
use Getopt::Std;
use IPC::Open3;
use Text::ParseWords qw(shellwords);    # shell-free argv split under RESTRICTED
use Symbol qw(gensym);
use IO::File;
use Term::ANSIColor;
use Text::Balanced qw(extract_bracketed);
use IO::Select;
use File::Temp qw(tempfile);
use Digest::MD5 qw(md5_hex);
use Cwd qw(getcwd);    # robust CWD; avoids fork()ing `pwd`, which fails on small/odd terminals

# Locate CCFE's own Perl modules relative to this file, so they are found both
# from the source tree (src/lib) and when installed (bin/../lib/perl5).  Using
# __FILE__ (not $0/FindBin) keeps this correct even when the program is
# require()d headlessly from the test suite.
use lib do {
    require Cwd;    # resolve a symlinked invocation (e.g. /usr/bin/ccfe -> ...)
    my $d = dirname( Cwd::abs_path(__FILE__) );
    ( "$d/lib", "$d/../lib/perl5" );
};
use CCFE::Restrict ();
use CCFE::Theme    ();
use CCFE::MenuFile ();    # pure .menu/.item parser (see load_menu)
use CCFE::FormFile ();    # pure .form parser (see load_form)
use CCFE::Config   ();    # pure .conf section tokenizer (see load_config)
use CCFE::Action   ();    # pure action-string parser (see do_menu/do_form)
use CCFE::Layout   ();    # pure form value-column/page geometry (see do_form)
use CCFE::Context  ();    # explicit run-state container (M7 de-globalisation)
use FindBin ();    # to locate the program at runtime (see the path block below)

# M7 Phase 6 (capstone): this legacy script predates `use strict`.  Its package
# globals -- constants, lookup tables, the search-path arrays, message strings
# and the few intentionally-global runtime vars ($cpid/$tmpfh, owned by the
# signal handlers) -- are declared here so the file runs under strict.  The
# de-globalisation (Phases 1-5) moved the mutable per-screen/config/run state
# onto lexicals and $ctx; what remains global is genuinely program-wide.
## BEGIN-OUR (formatted; scalars, then arrays, then hashes)
our (
    $ALL_FIELDS_IDS_TAG, $ASKS_FIELD_PAD, $ASKS_FIELD_SIZE, $ASKS_WIN_COLS,
    $ASKS_WIN_FTR_ROWS, $ASKS_WIN_ROWS, $BAD_SHELL_MSG, $BAD_SHELL_TITLE,
    $BFIELD_DEFAULT, $BFIELD_NO, $BFIELD_NO_DESCR, $BFIELD_NULL,
    $BFIELD_NULL_DESCR, $BFIELD_YES, $BFIELD_YES_DESCR, $BIG_OUTPUT_MSG,
    $BIG_OUTPUT_TITLE, $BINDIR, $BOOLEAN, $BOOLEAN_FIELD_SIZE, $CALLNAME,
    $CALL_SHELL_MSG, $CALL_SYS_ES_MSG, $CALL_SYS_MSG, $CONFIRM_DESCR_NO,
    $CONFIRM_DESCR_YES, $CONFIRM_TITLE, $CURSES_ACTIVE, $DEBUG, $DESCR,
    $DMENU_DEF_FNAME, $EMPTY_LIST_MSG, $EMPTY_LIST_TITLE,
    $ERR_EMPTY_FIELD_MSG, $ERR_EMPTY_FIELD_TITLE, $ERR_LOAD_INITIAL_OBJ,
    $ES_CANCEL, $ES_EXIT, $ES_FOPEN_ERR, $ES_FOPEN_ERR_MSG, $ES_NOT_FOUND,
    $ES_NOT_FOUND_MSG, $ES_NO_ERR, $ES_NO_ERR_MSG, $ES_NO_ITEMS,
    $ES_NO_ITEMS_MSG, $ES_SYNTAX_ERR, $ES_SYNTAX_ERR_MSG, $ES_USER_REQ,
    $ETCDIR, $FALSE, $FIELD_LMARGIN, $FIELD_RMARGIN, $FIELD_VALUE_GAP,
    $FORMEXT, $FORM_ARGV_ID, $FORM_ERR_TITLE, $FOUND_NONE_MSG,
    $FOUND_NONE_TITLE, $FSEP_ID_PRFX, $FS_BOTTOM_ROWS, $FS_HEADER_ROWS,
    $FS_TOP_ROWS, $HAS_COLOR, $HOSTNAME, $HTAB_COLS, $INIT_DISABLE_FIELDS,
    $INIT_ENABLE_FIELDS, $INIT_FORM_ERR_MSG, $INIT_REMOVE_FIELDS,
    $KEY_ENTER_LABEL, $KEY_F10_LABEL, $KEY_F1_LABEL, $KEY_F2_LABEL,
    $KEY_F3_LABEL, $KEY_F4_LABEL, $KEY_F5_LABEL, $KEY_F6_LABEL, $KEY_F7_LABEL,
    $KEY_F8_LABEL, $KEY_F9_LABEL, $KEY_FIND_LABEL, $KEY_FNEXT_LABEL,
    $KEY_INTR_LABEL, $KEY_SELALL_LABEL, $KEY_UNSELALL_LABEL, $LANG_ID,
    $LEGACY_DIR, $LIBDIR, $LIST_CMD_ERR_MSG, $LIST_CMD_ERR_TITLE,
    $LOAD_FORM_ERR_MSG, $LOAD_MENU_ERR_MSG, $LOGDIR, $LOG_ACTION_CMD,
    $LOG_ACTION_OUT, $LOG_DATE, $LOG_DEFAULT_CMD, $LOG_FIELDS_VAL,
    $LOG_INITFORM_OUT, $LOG_LIST_CMD, $LOG_MENU_CHOICE, $LOG_NORMAL,
    $LOG_REQUESTED, $LOG_SCAN_PATHS, $LOG_SYSCALL_ENV, $LOG_WRITE_ERROR_MSG,
    $LOG_WRITE_ERROR_TITLE, $LW_COLS, $LW_FOOTER_ROWS, $LW_PAD_COLS, $LW_ROW0,
    $MAIN_PATH, $MARK_PRIV_SHCUTS, $MENUEXT, $MENU_ERR_TITLE,
    $MIN_ITEMS_FOR_FIND, $MOUSE_ON, $MSGDIR, $MSG_WIN_BMSG, $MSG_WIN_ROWS,
    $MSG_WIN_TITLE, $MS_BOTTOM_ROWS, $MS_HEADER_ROWS, $MS_TOP_ROWS, $NO,
    $NORMAL, $NULLBOOLEAN, $NULL_FACTION_MSG, $NULL_FACTION_TITLE,
    $NULL_LIST_MSG, $NULL_LIST_TITLE, $NUMERIC, $OBJDIR, $OFF, $ON, $PERS_DIR,
    $PERS_WRITE_ERROR_MSG, $PERS_WRITE_ERROR_TITLE, $PREFIX, $PRIV_DIR,
    $RB_FAILED_MSG, $RB_LINES_MSG, $RB_OK_MSG, $RB_RUNNING_MSG, $RB_TIME_MSG,
    $RB_TITLE, $REALNAME, $RESTRICTED_MSG, $RESTRICTED_TITLE, $RS_BOTTOM_ROWS,
    $RS_HEADER_ROWS, $RS_INFO_ID, $RS_STDERR_ID, $RS_STDOUT_ID, $RS_TOP_ROWS,
    $SAVE_DETAILED, $SAVE_DETAILED_DESCR, $SAVE_ERROR_MSG, $SAVE_ERROR_TITLE,
    $SAVE_FIELDVAL_MSG, $SAVE_FIELDVAL_TITLE, $SAVE_FNAME_PROMPT,
    $SAVE_FNAME_TITLE, $SAVE_SCRIPT, $SAVE_SCRIPT_DESCR, $SAVE_SIMPLE,
    $SAVE_SIMPLE_DESCR, $SAVE_TYPE_TITLE, $SEARCH_PTRN_PROMPT,
    $SEARCH_PTRN_TITLE, $SEPARATOR, $SEP_LINE, $SEP_LINE_DOUBLE, $SEP_TEXT,
    $SEP_TEXT_CENTER, $SHOW_ACTION_TITLE, $SIMPLE, $SR_BUFF_SIZE, $STRING,
    $THEMEDIR, $TRUE, $UCSTRING, $USERNAME, $USR_CFG, $USR_OBJ, $VERSION,
    $VERSION_DATE, $VERSION_YEAR, $WAIT_MSG_MSG, $WRKDIR, $YES, $attrk,
    $attrv, $called_form, $ch, $choice, $cpid, $descr, $es, $exec_hh,
    $exec_mm, $exec_ss, $i, $id, $lflags_size, $mlmargin, $mwin, $mwinr, $opt,
    $out, $ovl_mode, $p, $pad_lines, $path, $pid, $prev_wdir, $res,
    $rflags_size, $s, $scan, $search_string, $shcut_type, $text, $tmpfh,
    $twin,
    @CONFIRM_ITEMS, @ERR_LITTLE_SCREEN, @ERR_WRONG_FPATH, @FORM_TOP_MSG,
    @FSKeys, @LW_DISPLAY_TOP_MSG, @LW_MULTIVAL_TOP_MSG, @LW_SINGLEVAL_TOP_MSG,
    @MENU_TOP_MSG, @MSKeys, @RSKeys, @cnf_path, @es_str, @flist,
    @fn_key_functions, @lines, @mf_path,
    %bool_vals, %layout_vals, %options, %sep_type_vals, %type_vals,
);
## END-OUR

# Optional display-width support.  In a UTF-8 locale a label/title can occupy
# fewer screen columns than it has bytes (e.g. "caf\xc3\xa9" is 5 bytes, 4
# columns) and a CJK glyph occupies two columns; ncursesw already lays the
# screen out by columns, so CCFE's own layout maths must measure columns too,
# not bytes.  Text::CharWidth::mbswidth() (Debian libtext-charwidth-perl)
# reports the column width per the locale, matching ncursesw exactly; if it is
# absent disp_width() falls back to length(), which is column-identical in a
# single-byte locale.  See disp_width() below.
our $HAVE_CHARWIDTH = eval { require Text::CharWidth; 1 };

# The explicit run-state container (M7 de-globalisation, REFACTOR.md §3.2).
# Built first so the config defaults and load_config below fill $ctx->{cfg}
# rather than scattered package globals; see M7-CTX-PLAN.md (Phase 4).
our $ctx = CCFE::Context::new();

$VERSION      = '2.2';
$VERSION_DATE = '11/06/2026';
$VERSION_YEAR = '2009, 2026';

# Install paths are resolved at runtime from this program's own location, so
# the same unmodified file works at any prefix -- no install-time templating.
# $PREFIX is the directory above bin/ (FindBin::RealBin resolves a PATH lookup
# or a symlinked instance name to the real bin dir).  Each directory may be
# overridden by an environment variable, which is how an FHS package points at
# a split tree (e.g. CCFE_ETC_DIR=/etc/ccfe).
$PREFIX = $ENV{CCFE_PREFIX} || dirname($FindBin::RealBin);

$ETCDIR   = $ENV{CCFE_ETC_DIR}   || "$PREFIX/etc";
$BINDIR   = $ENV{CCFE_BIN_DIR}   || "$PREFIX/bin";
$LIBDIR   = "$PREFIX/lib";
$LOGDIR   = $ENV{CCFE_LOG_DIR}   || "$PREFIX/log";
$MSGDIR   = $ENV{CCFE_MSG_DIR}   || "$PREFIX/msg";
$OBJDIR   = $ENV{CCFE_OBJ_DIR}   || "$PREFIX/share/ccfe/objects";
$THEMEDIR = $ENV{CCFE_THEME_DIR} || "$PREFIX/share/ccfe/themes";

$REALNAME        = 'ccfe';
$DESCR           = 'The Curses Command Front-end';
$CALLNAME        = basename($0);
$USERNAME        = ( getpwuid($>) )[0];
$HOSTNAME        = ( split /\./, hostname )[0];
$MENUEXT         = '.menu';
$FORMEXT         = '.form';
$DMENU_DEF_FNAME = 'definition';

# Per-user locations follow the XDG base-directory spec, with the legacy
# ~/.ccfe kept as a fallback so existing setups keep working.
$USR_CFG    = ( $ENV{XDG_CONFIG_HOME} || "$ENV{HOME}/.config" ) . "/$REALNAME";
$USR_OBJ    = ( $ENV{XDG_DATA_HOME} || "$ENV{HOME}/.local/share" ) . "/$REALNAME";
$LEGACY_DIR = "$ENV{HOME}/.$REALNAME";
$PRIV_DIR   = $USR_OBJ;
$PERS_DIR   = "$PRIV_DIR/persistent";

$NO  = $OFF = $FALSE = 0;
$YES = $ON  = $TRUE  = 1;

$DEBUG            = $NO;
$ctx->{cfg}{PERMIT_DEBUG}     = $YES;
$MARK_PRIV_SHCUTS = $YES;

$MAIN_PATH = '/usr/bin:/bin:/usr/local/bin:/sbin:/usr/sbin';
$ctx->{cfg}{PATH}      = "$ENV{HOME}/bin";

$ctx->{cfg}{LOG_FNAME}        = "$LOGDIR/$USERNAME.log";
$LOG_DATE         = $NO;
$LOG_NORMAL       = 1;
$LOG_LIST_CMD     = 2;
$LOG_DEFAULT_CMD  = 4;
$LOG_ACTION_CMD   = 8;
$LOG_FIELDS_VAL   = 16;
$LOG_MENU_CHOICE  = 32;
$LOG_ACTION_OUT   = 64;
$LOG_SYSCALL_ENV  = 128;
$LOG_SCAN_PATHS   = 256;
$LOG_INITFORM_OUT = 512;
$ctx->{cfg}{LOG_LEVEL}        = $LOG_NORMAL;
$LOG_REQUESTED    = $NO;

$LW_COLS        = 76;
$LW_ROW0        = 2;
$LW_PAD_COLS    = 160;
$LW_FOOTER_ROWS = 3;

$MSG_WIN_ROWS = 5;

$MS_HEADER_ROWS = 2;
$MS_TOP_ROWS    = 2;
$MS_BOTTOM_ROWS = 0;
$ctx->{cfg}{MS_FOOTER_ROWS} = 2;

$FS_HEADER_ROWS = 2;
$FS_TOP_ROWS    = 3;
$FS_BOTTOM_ROWS = 0;
$ctx->{cfg}{FS_FOOTER_ROWS} = 2;

$RS_HEADER_ROWS = 2;
$RS_TOP_ROWS    = 1;
$RS_BOTTOM_ROWS = 0;
$ctx->{cfg}{RS_FOOTER_ROWS} = 2;

$ES_NO_ERR     = 0;
$ES_SYNTAX_ERR = 1;
$ES_FOPEN_ERR  = 2;
$ES_NOT_FOUND  = 3;
$ES_NO_ITEMS   = 4;
$ES_USER_REQ   = 253;
$ES_CANCEL     = 254;
$ES_EXIT       = 255;

$NUMERIC     = 1;
$BOOLEAN     = 2;
$NULLBOOLEAN = 6;
$STRING      = 8;
$UCSTRING    = 24;
$SEPARATOR   = 256;

$SEP_TEXT        = 1;
$SEP_TEXT_CENTER = 2;
$SEP_LINE        = 3;
$SEP_LINE_DOUBLE = 4;

$BOOLEAN_FIELD_SIZE = 3;
$BFIELD_YES         = 'YES';
$BFIELD_NO          = 'NO';
$BFIELD_NULL        = '';
$BFIELD_DEFAULT     = $BFIELD_NO;
# Defaults so a headless load_form (e.g. --dump/-k, before load_msgs) does not
# read these undef; load_msgs overrides them with the localised descriptions.
$BFIELD_YES_DESCR   = 'Yes';
$BFIELD_NO_DESCR    = 'No';
$BFIELD_NULL_DESCR  = 'Not set';
$MIN_ITEMS_FOR_FIND = 5;

$INIT_REMOVE_FIELDS  = 'CCFE_REMOVE_FIELDS';
$INIT_ENABLE_FIELDS  = 'CCFE_ENABLE_FIELDS';
$INIT_DISABLE_FIELDS = 'CCFE_DISABLE_FIELDS';

$FORM_ARGV_ID = 'ARGV';

$ALL_FIELDS_IDS_TAG = '\*';
$FSEP_ID_PRFX       = 'CCFEFSEP';

$NORMAL      = 0;
$SIMPLE      = 1;
%layout_vals = (
    normal => $NORMAL,
    simple => $SIMPLE
);

$ASKS_WIN_ROWS     = 5;
$ASKS_WIN_COLS     = 78;
$ASKS_WIN_FTR_ROWS = 2;
$ASKS_FIELD_SIZE   = 40;

$SAVE_SIMPLE   = 'Simple';
$SAVE_DETAILED = 'Detailed';
$SAVE_SCRIPT   = 'Script';

$RS_INFO_ID   = 'C';
$RS_STDOUT_ID = 'O';
$RS_STDERR_ID = 'E';

$SR_BUFF_SIZE = 512;

# Menus/forms: system objects dir, then the user's XDG data dir, then the
# legacy ~/.ccfe.  Config: system etc, then XDG config, then legacy.
@mf_path = (
    "$OBJDIR/$CALLNAME",
    "$USR_OBJ/$CALLNAME",
    "$LEGACY_DIR/$CALLNAME",
);
@cnf_path = (
    "$ETCDIR/$REALNAME.conf",
    "$USR_CFG/$REALNAME.conf",
    "$LEGACY_DIR/$REALNAME.conf",
);
if ( $CALLNAME ne $REALNAME ) {
    push @cnf_path, "$ETCDIR/$CALLNAME.conf", "$USR_CFG/$CALLNAME.conf",
      "$LEGACY_DIR/$CALLNAME.conf";
}

%bool_vals = (
    yes => $YES,
    no  => $NO
);
%type_vals = (
    numeric     => $NUMERIC,
    boolean     => $BOOLEAN,
    nullboolean => $NULLBOOLEAN,
    string      => $STRING,
    ucstring    => $UCSTRING
);
%sep_type_vals = (
    text        => $SEP_TEXT,
    text_center => $SEP_TEXT_CENTER,
    line        => $SEP_LINE,
    line_double => $SEP_LINE_DOUBLE
);

@fn_key_functions =
  qw( back exit help list redraw reset_field save sel_items shell_escape show_action );

$ctx->{state}{SCREEN_DIR} = '';

$HTAB_COLS     = 2;
$FIELD_LMARGIN = 2;
$FIELD_RMARGIN = 2;

$ctx->{state}{child_es}     = 0;
$ctx->{state}{last_item_id} = '';
$ctx->{state}{pad_lines}    = 0;
undef $ctx->{state}{exec_args};
undef $cpid;
undef $tmpfh;

$SIG{INT} = sub {
    trace("SIGINT handler start - child PID $cpid");
    if ( defined($cpid) ) {
        trace(
            "PID $$ received SIGINT: waiting child (PID $cpid) to terminate..."
        );
        kill 15, $cpid;
        waitpid( $cpid, 0 );
        trace("PID $cpid terminated");
        my $msg = "PID $cpid execution interrupted by SIGINT!";
        undef $cpid;
        print $tmpfh "$RS_INFO_ID:\n";
        print $tmpfh "$RS_INFO_ID:$msg\n";
        $ctx->{state}{pad_lines} += 2;
    }
    trace("SIGINT handler end");
};

sub REAPER {
    my $child;
    while ( ( $child = waitpid( -1, WNOHANG ) ) > 0 ) {
        $ctx->{state}{child_es} = $? >> 8;
    }
    $SIG{CHLD} = \&REAPER;
}
$SIG{CHLD} = \&REAPER;

# Screen-column width of a (possibly UTF-8) string -- the unit ncursesw lays
# the screen out in.  Pure-ASCII strings (the overwhelming majority of labels)
# take the fast length() path; otherwise use mbswidth() when available.
sub disp_width {
    my ($s) = @_;
    return 0 unless defined $s;
    return length($s) if $s !~ /[^\x00-\x7f]/;    # ASCII: bytes == columns
    if ($HAVE_CHARWIDTH) {
        my $w = Text::CharWidth::mbswidth($s);
        return $w if defined $w && $w >= 0;        # -1 == has non-printables
    }
    return length($s);
}

# Theme helper, callable from a config *_attr value: the attribute bits for a
# foreground-over-background colour pair, e.g. `screen_attr = color_pair('white',
# 'blue')`.  $bg defaults to the terminal's own background (so color_pair('cyan')
# == a plain cyan foreground).  The pair is created after start_color(); see the
# colour-enable block below and CCFE::Theme::pair_for().
sub color_pair {
    my ( $fg, $bg ) = @_;
    return COLOR_PAIR( CCFE::Theme::pair_for( $fg, $bg ) );
}

# Resolve a config attribute expression to its numeric value WITHOUT eval
# (M8/TD-1d: a config *_attr value is data, never code).  Accepts the documented
# grammar -- the A_* video attributes, COLOR_PAIR(n), color_pair('fg','bg'), a
# bare integer, and `|`-combinations of those -- and returns undef on anything
# else, so a malformed config value is ignored (the caller keeps the default)
# instead of being able to inject Perl.
my %ATTR_CONST;
sub attr_value {
    my ($str) = @_;
    return undef unless defined $str;
    $str =~ s/^\s+//;
    $str =~ s/\s+$//;
    return undef if $str eq '';
    %ATTR_CONST = (
        A_NORMAL  => A_NORMAL,  A_BOLD      => A_BOLD,
        A_REVERSE => A_REVERSE, A_UNDERLINE => A_UNDERLINE,
        A_BLINK   => A_BLINK,   A_DIM       => A_DIM,
        A_STANDOUT => A_STANDOUT,
    ) unless %ATTR_CONST;

    my $val = 0;
    for my $tok ( split /\s*\|\s*/, $str ) {
        if ( exists $ATTR_CONST{$tok} ) {
            $val |= $ATTR_CONST{$tok};
        }
        elsif ( $tok =~ /^COLOR_PAIR\(\s*(\d+)\s*\)$/ ) {
            $val |= COLOR_PAIR($1);
        }
        elsif ( $tok =~ /^color_pair\(\s*'([a-z]+)'\s*,\s*'([a-z]+)'\s*\)$/ ) {
            $val |= color_pair( $1, $2 );
        }
        elsif ( $tok =~ /^-?\d+$/ ) {
            $val |= $tok;
        }
        else {
            return undef;    # outside the grammar -> ignore (no eval, no inject)
        }
    }
    return $val;
}

sub fatal {
    trace("FATAL: @_");
    clrtobot( 0, 0 );
    addstr( 0, 0, "@_\n" );
    refresh();
    sleep 2;
    endwin();
    exit 1;
}

sub usage {
    my $layouts = lc join( '|', keys(%layout_vals) );
    print << "EOF";

$DESCR.

  Usage: $CALLNAME [OPTION]... [SHORTCUT]

  Options:
    -c        : print some Configuration parameters and exit
    -d        : set verbose log for Debugging purposes
    -D NAME   : Dump menu/form NAME as JSON, then exit (no terminal needed)
    --dump N  : long form of -D
    -h        : print this (Help) message and exit
    -k NAME   : checK that menu/form NAME parses, then exit (no terminal needed)
    -l PATH   : set forms and menus Library directory to PATH
    -P        : list installed Plugins (--plugins) and exit
    -s        : print available Shortcuts and exit
    -v        : print Version informations and exit

  SHORTCUT: initial form or menu name (without extension)

EOF
    exit;
}

sub print_config {
    print << "EOF";
ETC_DIR=$ETCDIR
LIB_DIR=$LIBDIR
OBJ_DIR=$OBJDIR
THEME_DIR=$THEMEDIR
MSG_DIR=$MSGDIR
EOF
    exit;
}

sub trim {
    my ($string) = @_;
    for ($$string) {
        s/^\s+//;
        s/\s+$//;
    }
}

sub ralign {
    my ( $str, $size ) = @_;
    # Plain sprintf, not an eval-string: $str is data, never interpolated into
    # code (M8 audit -- removes a latent injection smell).
    return sprintf "% ${size}s", $str;
}

sub valid_shell {
    my ($shell) = @_;

    my $shells = '/etc/shells';
    my $found  = $NO;
    open( SHELLS, $shells ) || die("Error opening $shells:\n$!");
    while (<SHELLS>) {
        chop;
        $found = $YES if /^$shell$/;
    }
    close(SHELLS);
    return $found;
}

# ---- restricted-mode policy (security: prevent escape from the menu) -----
#
# When RESTRICTED is enabled (via the GLOBAL config) CCFE is a constrained
# front-end: the menu user must only be able to do what the menus allow.
# These helpers are consulted at every escape-capable site so the policy
# lives in one place.  See REFACTOR.md section 2.

# Thin tracing wrappers over the pure CCFE::Restrict policy: the decisions
# live in the module (unit-tested headlessly), the program just supplies its
# configuration and logs a denial.
sub restricted_denies_verb {
    my ( $verb, $args ) = @_;
    my $deny =
      CCFE::Restrict::denies_verb( $ctx->{cfg}{RESTRICTED},
        $ctx->{cfg}{RESTRICTED_ALLOW}, $verb, $args );
    trace("RESTRICTED: denied $verb:\"$args\" (not in RESTRICTED_ALLOW)")
      if $deny;
    return $deny;
}

sub restricted_denies_shell {
    my $deny = CCFE::Restrict::denies_shell($ctx->{cfg}{RESTRICTED});
    trace('RESTRICTED: interactive shell escape denied') if $deny;
    return $deny;
}

# Called once at startup -- CCFE itself does not rely on these variables after
# the dynamic libraries are already loaded.
sub harden_child_env {
    return CCFE::Restrict::harden_env( \%ENV );
}

{
    my $log_fh;         # persistent log handle, opened lazily and reused
    my $log_fh_name;    # the LOG_FNAME it was opened for

    # Append a pre-formatted string to the log, holding the handle open across
    # calls (TD-5).  Autoflush keeps every line on disk immediately, exactly as
    # the old open/append/close-per-line did, but without the per-line syscalls
    # in a streaming command's output capture.  3-arg open with an explicit
    # append mode so a crafted LOG_FNAME cannot smuggle a pipe or redirect.
    # Shared by trace() and the $SIG{__WARN__} handler.
    sub _log_write {
        my ($str) = @_;
        my $fname = $ctx->{cfg}{LOG_FNAME};
        return unless $fname;
        if ( !$log_fh or ( $log_fh_name // '' ) ne $fname ) {
            close($log_fh) if $log_fh;
            my $prev_umask = umask 0177;
            unless ( open( $log_fh, '>>', $fname ) ) {
                umask $prev_umask;
                $log_fh = undef;
                return;
            }
            umask $prev_umask;
            select( ( select($log_fh), $| = 1 )[0] );    # autoflush this handle
            $log_fh_name = $fname;
        }
        print {$log_fh} $str;
        return;
    }
}

sub trace {
    my ( $msg, $log_level ) = @_;
    $log_level //= 0;    # no level given -> 0 (logged only under DEBUG, as before)

    # TD-5: gate on LOG_FNAME and the log level *before* doing any timestamp or
    # caller work -- there is nothing to format if the line will not be logged.
    return unless $ctx->{cfg}{LOG_FNAME};

    my $log_it = $NO;
    if ( $ctx->{cfg}{LOG_LEVEL} & $log_level ) {
        $log_it = $YES;
        if ( $LOG_NORMAL & $log_level ) {
            $log_it = $NO if !$LOG_REQUESTED;
        }
    }
    $log_it = $YES if $DEBUG;
    return unless $log_it;

    my $caller = '';
    if ($DEBUG) {
        $caller = ( caller(1) )[3];
        $caller =~ s/^.*:://;
        $caller .= "[$$]: " if $caller;
    }

    my $now = '';
    if ($LOG_DATE) {
        my @months = qw( Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec );
        my @buff   = localtime(time);
        $now = sprintf "%s %02d %d %02d:%02d:%02d%s",
          $months[ $buff[4] ],
          $buff[3], $buff[5] + 1900, $buff[2], $buff[1], $buff[0],
          $DEBUG ? ' ' : "\n";
    }

    _log_write( sprintf "%s%s%s\n", $now, $caller, $msg );
    return;
}

sub get_lang_id {
    my $lang_id = 'C';

    return $lang_id;
}

sub load_msgs {
    my $id;
    my $fname = "$MSGDIR/$LANG_ID/$CALLNAME";

    my @msg_id = qw(NULL_LIST_MSG
      NULL_LIST_TITLE
      EMPTY_LIST_MSG
      EMPTY_LIST_TITLE
      LIST_CMD_ERR_MSG
      LIST_CMD_ERR_TITLE
      RESTRICTED_MSG
      RESTRICTED_TITLE
      NULL_FACTION_MSG
      NULL_FACTION_TITLE
      SAVE_FIELDVAL_MSG
      SAVE_FIELDVAL_TITLE
      BIG_OUTPUT_MSG
      BIG_OUTPUT_TITLE
      FOUND_NONE_MSG
      FOUND_NONE_TITLE
      SEARCH_PTRN_PROMPT
      SEARCH_PTRN_TITLE
      CALL_SYS_ES_MSG
      CALL_SYS_MSG
      MSG_WIN_BMSG
      MSG_WIN_TITLE
      BFIELD_YES_DESCR
      BFIELD_NO_DESCR
      BFIELD_NULL_DESCR
      CONFIRM_TITLE
      CONFIRM_DESCR_NO
      CONFIRM_DESCR_YES
      SHOW_ACTION_TITLE
      KEY_F1_LABEL
      KEY_F2_LABEL
      KEY_F3_LABEL
      KEY_F4_LABEL
      KEY_F5_LABEL
      KEY_F6_LABEL
      KEY_F7_LABEL
      KEY_F8_LABEL
      KEY_F9_LABEL
      KEY_F10_LABEL
      KEY_F11_LABEL
      KEY_F12_LABEL
      KEY_ENTER_LABEL
      KEY_INTR_LABEL
      KEY_FIND_LABEL
      KEY_FNEXT_LABEL
      KEY_SELALL_LABEL
      KEY_UNSELALL_LABEL
      CALL_SHELL_MSG
      WAIT_MSG_MSG
      FORM_ERR_TITLE
      LOAD_FORM_ERR_MSG
      INIT_FORM_ERR_MSG
      MENU_ERR_TITLE
      LOAD_MENU_ERR_MSG
      RB_TITLE
      RB_RUNNING_MSG
      RB_OK_MSG
      RB_FAILED_MSG
      RB_LINES_MSG
      RB_TIME_MSG
      SAVE_TYPE_TITLE
      SAVE_SIMPLE_DESCR
      SAVE_DETAILED_DESCR
      SAVE_SCRIPT_DESCR
      SAVE_FNAME_PROMPT
      SAVE_FNAME_TITLE
      SAVE_ERROR_MSG
      SAVE_ERROR_TITLE
      LOG_WRITE_ERROR_MSG
      LOG_WRITE_ERROR_TITLE
      PERS_WRITE_ERROR_TITLE
      PERS_WRITE_ERROR_MSG
      ERR_LITTLE_SCREEN[0]
      ERR_LITTLE_SCREEN[1]
      ERR_WRONG_FPATH[0]
      ERR_WRONG_FPATH[1]
      ERR_LOAD_INITIAL_OBJ
      ES_NO_ERR_MSG
      ES_SYNTAX_ERR_MSG
      ES_FOPEN_ERR_MSG
      ES_NOT_FOUND_MSG
      ES_NO_ITEMS_MSG
      LW_MULTIVAL_TOP_MSG[0]
      LW_MULTIVAL_TOP_MSG[1]
      LW_MULTIVAL_TOP_MSG[2]
      LW_SINGLEVAL_TOP_MSG[0]
      LW_SINGLEVAL_TOP_MSG[1]
      LW_SINGLEVAL_TOP_MSG[2]
      LW_DISPLAY_TOP_MSG[0]
      LW_DISPLAY_TOP_MSG[1]
      LW_DISPLAY_TOP_MSG[2]
      FORM_TOP_MSG[0]
      FORM_TOP_MSG[1]
      MENU_TOP_MSG[0]
      MENU_TOP_MSG[1]
      ERR_EMPTY_FIELD_MSG
      ERR_EMPTY_FIELD_TITLE
      BAD_SHELL_MSG
      BAD_SHELL_TITLE);

    foreach $id (@msg_id) {
        eval "\$$id = \"ERROR_OR_UNDEFINED_MSG:$id\"";
    }

    open( INF, $fname ) or die("$CALLNAME: Error opening file $fname\n");
    while (<INF>) {
        chop;
        next if /^\s*#/;
        next if /^$/;
        s/\s*#.*$//;
        s/^\s*([\w\[\]]+)\s*=\s*(.+)?/\$\U$1\E=$2/;
        $id = uc($1);
        ($id) = (/^\s*(\S+)\s*=/) if !$id;
        if ( in( $id, @msg_id ) ) {
            eval;
        }
        else {
            trace("unknown message ID '$id'");
        }
        while ( !$LW_MULTIVAL_TOP_MSG[$#LW_MULTIVAL_TOP_MSG] ) {
            pop(@LW_MULTIVAL_TOP_MSG);
        }
        while ( !$LW_SINGLEVAL_TOP_MSG[$#LW_SINGLEVAL_TOP_MSG] ) {
            pop(@LW_SINGLEVAL_TOP_MSG);
        }
        while ( !$LW_DISPLAY_TOP_MSG[$#LW_DISPLAY_TOP_MSG] ) {
            pop(@LW_DISPLAY_TOP_MSG);
        }
        $CONFIRM_ITEMS[0] = "$BFIELD_NO $CONFIRM_DESCR_NO";
        $CONFIRM_ITEMS[1] = "$BFIELD_YES $CONFIRM_DESCR_YES";
    }
    close(INF);
}

sub exec_command {
    my ( $cmd, $extra_path, $stdout_ref, $stderr_ref ) = @_;

    my ( $prev_path, $prev_wdir );

    $prev_wdir = getcwd();
    chdir "$ctx->{state}{SCREEN_DIR}";
    trace( "Changed CWD from $prev_wdir to " . getcwd() );
    $prev_path = $ENV{PATH};
    $ENV{PATH} = sprintf "%s%s:%s", $MAIN_PATH, $MAIN_PATH ? ":$ctx->{cfg}{PATH}" : '',
      $ctx->{state}{SCREEN_DIR};
    if ($extra_path) {
        my @dirs = split /:/, $extra_path;
        foreach $i ( 0 .. $#dirs ) {
            $dirs[$i] = "$ctx->{state}{SCREEN_DIR}/$dirs[$i]" unless $dirs[$i] =~ /^\//;
        }
        $extra_path = join( ':', @dirs );
    }
    $ENV{PATH} .= ":$extra_path" if $extra_path;
    trace( "PATH=\"$ENV{PATH}\"", $LOG_SYSCALL_ENV );

    trace("executing \"$cmd\"");
    @$stdout_ref = ();
    @$stderr_ref = ();
    local *CATCHERR = IO::File->new_tmpfile;
    my $pid =
      open3( gensym, \*CATCHOUT, ">&CATCHERR", $ctx->{cfg}{OPEN3_SHELL}, '-c', $cmd );
    while (<CATCHOUT>) {
        push @$stdout_ref, $_;
    }
    waitpid( $pid, 0 );
    seek CATCHERR, 0, 0;
    while (<CATCHERR>) {
        push @$stderr_ref, $_;
    }
    $ENV{PATH} = $prev_path;
    chdir "$prev_wdir";
    trace( "Restored CWD to " . getcwd() );
    @$stdout_ref = map { s/\n//; $_ } @$stdout_ref;
    @$stderr_ref = map { s/\n//; $_ } @$stderr_ref;
    @$stdout_ref = map { s/\r//; $_ } @$stdout_ref;
    @$stderr_ref = map { s/\r//; $_ } @$stderr_ref;

    close(CATCHOUT);
    close(CATCHERR);
    return (@$stderr_ref) ? $FALSE : $TRUE;
}

sub init_title {
    my ( $win, $winRows, $title ) = @_;

    $title =~ s/^\s+//;
    $title =~ s/\s+$//;
    addstr( $win, 0, 0, $USERNAME . '@' . $HOSTNAME ) if ( $ctx->{cfg}{LAYOUT} == $NORMAL );
    attron( $win, $ctx->{cfg}{TITLE_ATTR} ) if ( $ctx->{cfg}{LAYOUT} == $NORMAL );
    addstr( $win, 0, int( ( $COLS - disp_width($title) ) / 2 ), $title );
    attroff( $win, $ctx->{cfg}{TITLE_ATTR} ) if ( $ctx->{cfg}{LAYOUT} == $NORMAL );
    hline( $win, $winRows - 1, 0, ACS_HLINE, $COLS ) if ( $ctx->{cfg}{LAYOUT} == $NORMAL );
}

sub init_top {
    my ( $win, $has_border, $winY0, $winRows, @tlines ) = @_;
    my ( $maxLen, $i, $tlmargin, $maxY, $maxX );

    getmaxyx( $win, $maxY, $maxX );
    $maxLen = 0;
    foreach $i ( 0 .. $#tlines ) {
        $maxLen = length( $tlines[$i] ) if length( $tlines[$i] ) > $maxLen;
    }
    if ( $ctx->{cfg}{LAYOUT} == $SIMPLE ) {
        $tlmargin = $has_border ? 2 : 0;
    }
    else {
        $tlmargin = int( ( $maxX - $maxLen ) / 2 ) + ( $has_border ? 1 : 0 );
    }

    foreach $i ( 0 .. $winRows - 1 ) {
        last if $i > $#tlines;
        addstr( $win, $winY0 + $i, $tlmargin, $tlines[$i] );
    }
}

sub init_footer {
    my ( $win, $has_border, $nRows, @keysList ) = @_;
    my ( $nOptPerRow, $labelSize, $y, $x, $y0, $x0, $i, $maxY,
        $maxX );

    sub sort_fnkeys {
        my ($klist_ref) = @_;

        my @sorted = sort {
            if ( $ctx->{cfg}{keys}{$a}{key} !~ /F[0-9]+/ )
            {
                return 0;
            }
            elsif ( $ctx->{cfg}{keys}{$b}{key} !~ /F[0-9]+/ ) {
                return 0;
            }
            else {
                return
                  substr( $ctx->{cfg}{keys}{$a}{key}, 1 ) <=> substr( $ctx->{cfg}{keys}{$b}{key}, 1 );
            }
        } @$klist_ref;
        @$klist_ref = @sorted;
    }

    getmaxyx( $win, $maxY, $maxX );
    $y0 = $maxY - $nRows - ( $has_border ? 1 : 0 );
    $x0 = $has_border ? 1 : 0;
    $i = 0;
    while ( $i <= $#keysList ) {
        if ( !$ctx->{cfg}{keys}{ $keysList[$i] }{label} or !$ctx->{cfg}{keys}{ $keysList[$i] }{key} ) {
            splice( @keysList, $i, 1 );
        }
        else {
            $i++;
        }
    }
    sort_fnkeys( \@keysList );
    if ( $nRows > 1 ) {
        $nOptPerRow = int( ( scalar @keysList / ( $nRows - 1 ) ) + .5 );
    }
    else {
        $nOptPerRow = scalar @keysList;
    }
    $labelSize = int( ( $maxX + 1 ) / $nOptPerRow );

    hline( $win, $y0, $x0, ACS_HLINE, $maxX - ( $has_border ? 2 : 0 ) )
      if ( $ctx->{cfg}{LAYOUT} == $NORMAL );
    if ( $ctx->{cfg}{LAYOUT} == $NORMAL and $has_border ) {
        addch( $win, $y0, $x0 - 1,   ACS_LTEE );
        addch( $win, $y0, $maxX - 1, ACS_RTEE );
    }
    $x = 0;
    $y = $y0++;

    foreach $i ( 1 .. $nRows - 1 ) {
        addstr(
            $win, $y + $i,
            $has_border ? 1 : 0,
            ' ' x ( $maxX - ( $has_border ? 2 : 0 ) )
        );
    }

    foreach $i ( 0 .. $#keysList ) {
        if ( $i % ($nOptPerRow) == 0 ) {
            $y++;
            $x = $x0;
        }
        addstr( $win, $y, $x, "$ctx->{cfg}{keys}{$keysList[$i]}{key}" );
        addstr( $win, "$ctx->{cfg}{keys}{$keysList[$i]}{label}" );
        if ( $ctx->{cfg}{LAYOUT} == $NORMAL ) {
            # The control-key label (e.g. "F4") is highlighted.  A configured
            # $ctx->{cfg}{KEY_ATTR} (e.g. a colour pair) takes over; otherwise keep the
            # original bkgd-relative reverse so it stands out either way.
            my $ka =
              defined $ctx->{cfg}{KEY_ATTR}
              ? $ctx->{cfg}{KEY_ATTR}
              : ( ( getbkgd($win) & A_REVERSE ) ? A_NORMAL : A_REVERSE );
            # chgat() takes the colour pair as a separate argument, so extract
            # it from $ka (0 = no colour, i.e. the monochrome default).
            chgat( $win, $y, $x, length( $ctx->{cfg}{keys}{ $keysList[$i] }{key} ),
                $ka, PAIR_NUMBER($ka), 0 );    # 0 = NULL opts pointer
        }
        $x += $labelSize;
    }
}

sub call_shell {
    my ( $prompt, $prev_cwd );

    $prev_cwd = getcwd();
    chdir $ENV{HOME};
    $prompt = sprintf( "%s%s ", $CALLNAME, $> ? '$' : '#' );
    def_prog_mode();
    endwin();
    system("clear");
    print "$CALLNAME: $CALL_SHELL_MSG\n\n";
    system("PS1=\"$prompt\" $ctx->{cfg}{USER_SHELL}");
    reset_prog_mode();
    chdir $prev_cwd;
}

sub call_system {
    my ( $wait_key, $cmd ) = @_;

    my ($res);
    def_prog_mode();
    endwin();
    my $prev_path = $ENV{PATH};
    $ENV{PATH} = sprintf "%s%s", $MAIN_PATH, $MAIN_PATH ? ":$ctx->{cfg}{PATH}" : '';
    system("clear");
    trace("run \"$cmd\"");
    if ( $ctx->{cfg}{RESTRICTED} ) {
        # Shell-free under RESTRICTED (TD-1c): parse to argv and exec directly,
        # so the allowlisted program name is what actually runs -- no `;`/`&&`/
        # `$()`/backtick chaining and no %{field} metacharacter injection slip
        # through /bin/sh.  run: stays the explicit shell verb.
        my @argv = shellwords($cmd);
        $res = @argv ? ( system { $argv[0] } @argv ) : -1;
    }
    else {
        $res = system($cmd);
    }
    $res = $res == -1 ? 127 : ( $res >> 8 );
    trace("command exited with status $res");

    if ( $wait_key or $res != 0 ) {
        local $SIG{INT} = 'IGNORE';
        print color 'reverse';
        print "$CALLNAME: $CALL_SYS_ES_MSG $res - " if $res;
        print $CALL_SYS_MSG;
        print color 'reset';
        system "stty", '-icanon', 'eol', "\001";
        getc(STDIN);
        system "stty", 'icanon', 'eol', '^@';
    }
    $ENV{PATH} = $prev_path;
    reset_prog_mode();
}

sub disp_msg {
    my ( $pwin, $msg, $title ) = @_;
    my ( $panel, $win, $ch, $width );

    my $win_bg_attr = $ctx->{cfg}{LAYOUT} == $SIMPLE ? A_NORMAL : A_REVERSE;
    my $bottom_attr = A_NORMAL;

    $msg = substr( $msg, 0, $COLS - 4 ) if length($msg) > $COLS - 4;
    $width = disp_width($msg);
    if ( disp_width($MSG_WIN_BMSG) > $width ) {
        $width = disp_width($MSG_WIN_BMSG);
    }
    $win = newwin(
        $MSG_WIN_ROWS, $width + 4,
        int( ( $LINES - $MSG_WIN_ROWS ) / 2 ),
        int( ( $COLS - $width ) / 2 ) - 1
    );
    bkgd( $win, $win_bg_attr );
    box( $win, 0, 0 );
    keypad( $win, $ON );
    $panel = new_panel($win);
    $title = $MSG_WIN_TITLE unless $title;
    if ($title) {
        $title = " $title ";
        addstr( $win, 0, 2 + int( ( $width - disp_width($title) ) / 2 ),
            $title );
    }
    addstr( $win, 1, 2 + int( ( $width - disp_width($msg) ) / 2 ), $msg );
    addstr( $win, 3, 2 + int( ( $width - disp_width($MSG_WIN_BMSG) ) / 2 ),
        $MSG_WIN_BMSG );
    chgat( $win, 3, 1, $width + 2, $bottom_attr, 0, 0 );
    refresh($win);
    $ch = getch($win);
    del_panel($panel);
    delwin($win);
    refresh($pwin);
    return $ch;
}

sub open_wait_msg {
    my ($title) = @_;
    my ( $panel, $win,         $ch, $width );
    my ( $msg,   $win_bg_attr, $y0, $msg_x0 );

    $msg = $WAIT_MSG_MSG;
    if ( $ctx->{cfg}{LAYOUT} == $SIMPLE ) {
        $width       = 62;
        $win_bg_attr = A_NORMAL;
        $y0          = $LINES - 3;
        $msg_x0      = 2;
    }
    else {
        $width       = length($msg);
        $win_bg_attr = A_REVERSE;
        $y0          = int( ( $LINES - 3 ) / 2 );
        $msg_x0      = 2 + int( ( $width - length($msg) ) / 2 );
    }

    $win = newwin( 3, $width + 4, $y0, int( ( $COLS - $width ) / 2 ) );
    bkgd( $win, $win_bg_attr );
    box( $win, 0, 0 );
    $panel = new_panel($win);
    $title = $MSG_WIN_TITLE unless $title;
    if ($title) {
        $title = " $title ";
        addstr( $win, 0, 2 + int( ( $width - length($title) ) / 2 ), $title );
    }
    addstr( $win, 1, $msg_x0, $msg );
    refresh($win);
    return ( $panel, $win );
}

sub close_wait_msg {
    my ( $panel, $win, $parent_win ) = @_;

    del_panel($panel);
    delwin($win);
    refresh($parent_win);
}

sub ask_string {
    my ( $title, $prompt, $default ) = @_;
    my ( $panel, $win, $ch, $width, $height );
    my ( $field, $cform, $x0, $y0, $swin, $es, $strbuff );
    my @fp;
    my @fset;

    my $win_bg_attr = $ctx->{cfg}{LAYOUT} == $SIMPLE ? A_NORMAL : A_REVERSE;
    my $lmargin     = 1;
    my $prompt_x    = $FIELD_LMARGIN;
    my $prompt_y    = 0;
    my $field_x     = $FIELD_LMARGIN + length($prompt) + 1;
    my $field_y     = 0;

    $prompt = substr( $prompt, 0, $COLS - 4 ) if length($prompt) > $COLS - 4;
    $width  = $ASKS_WIN_COLS;
    $height = $ASKS_WIN_ROWS;
    $x0     = int( ( $COLS - $width ) / 2 );
    $y0     = int( ( $LINES - $height ) / 2 );
    if ( $ctx->{cfg}{LAYOUT} == $SIMPLE ) {
        $height   = 10;
        $y0       = $LINES - $height;
        $prompt_x = 1;
        $prompt_y = 2;
        $field_x  = 1;
        $field_y  = 4;
    }
    $win = newwin( $height, $width, $y0, $x0 );
    bkgd( $win, $win_bg_attr );
    $swin = derwin( $win, $height - 2 - $ASKS_WIN_FTR_ROWS, $width - 2, 1, 1 );
    box( $win, 0, 0 );
    $panel = new_panel($win);
    if ($title) {
        $title = " $title ";
        addstr( $win, 0, 1 + int( ( $width - length($title) ) / 2 ), $title );
    }
    init_footer( $win, $YES, $ASKS_WIN_FTR_ROWS, qw( help back exit ) );

    $field = new_field( 1, length($prompt), $prompt_y, $prompt_x, 0, 0 );
    if ( $field eq '' ) { fatal("ask_string().new_field.prompt failed") }
    set_field_buffer( $field, 0, $prompt );
    set_field_back( $field, $win_bg_attr );
    field_opts_off( $field, O_ACTIVE );
    field_opts_off( $field, O_EDIT );
    push @fp,   $field;
    push @fset, ${$field};

    $field = new_field( 1, $ASKS_FIELD_SIZE, $field_y, $field_x, 0, 0 );
    if ( $field eq '' ) {
        fatal("ask_string().new_field.value failed");
    }
    set_field_pad( $field, $ASKS_FIELD_PAD );
    set_field_buffer( $field, 0, $default ) if $default;
    set_field_back( $field, $ctx->{cfg}{valueBg} );
    field_opts_on( $field, O_BLANK );
    field_opts_off( $field, O_AUTOSKIP );
    push @fp,   $field;
    push @fset, ${$field};

    push @fset, 0;
    # new_form() stores this pointer WITHOUT copying the array (ncurses
    # behaviour), so the packed buffer must outlive the form (freed below).
    # An inline pack() temporary left a dangling pointer -- see do_menu().
    my $fields_buf = pack 'L!*', @fset;
    $cform = new_form($fields_buf);
    if ( $cform eq '' ) { fatal("ask_string.new_form() failed") }
    set_form_win( $cform, $win );
    set_form_sub( $cform, $swin );
    keypad( $win, $ON );
    post_form($cform);
    if ($ovl_mode) {
        form_driver( $cform, REQ_OVL_MODE );
    }
    else {
        form_driver( $cform, REQ_INS_MODE );
    }
    form_driver( $cform, REQ_END_LINE );

    curs_set($ON) if $ctx->{cfg}{HIDE_CURSOR};
    while (1) {
        $ch = getch($win);
        if ( $ch == KEY_LEFT ) {
            form_driver( $cform, REQ_LEFT_CHAR );
        }
        elsif ( $ch == KEY_RIGHT ) {
            form_driver( $cform, REQ_RIGHT_CHAR );
        }
        elsif ( $ch == KEY_UP or $ch == KEY_DOWN ) {
        }
        elsif ( $ch == KEY_HOME ) {
            form_driver( $cform, REQ_BEG_FIELD );
        }
        elsif ( $ch == KEY_END ) {
            form_driver( $cform, REQ_END_FIELD );
        }
        elsif ( $ch == KEY_DC ) {
            form_driver( $cform, REQ_DEL_CHAR );
        }
        elsif ( ord($ch) == 8 or ord($ch) == 127 ) {
            form_driver( $cform, REQ_DEL_PREV );
        }
        elsif ( $ch == KEY_IC ) {
            if ($ovl_mode) {
                $ovl_mode = $FALSE;
                form_driver( $cform, REQ_INS_MODE );
            }
            else {
                $ovl_mode = $TRUE;
                form_driver( $cform, REQ_OVL_MODE );
            }
        }
        elsif ( $ch == KEY_BACKSPACE ) {
            form_driver( $cform, REQ_DEL_PREV );
        }
        elsif ( $ch == $ctx->{cfg}{keys}{back}{code} or ord($ch) == 27 ) {
            $es = $ES_CANCEL;
            last;
        }
        elsif ( $ch == $ctx->{cfg}{keys}{exit}{code} ) {
            $es = $ES_EXIT;
            last;
        }
        elsif ( $ch >= KEY_F(1) and $ch <= KEY_F(12) ) {
            beep();
        }
        elsif ( $ch eq "\r" or $ch eq "\n" ) {
            form_driver( $cform, REQ_VALIDATION );
            last;
        }
        elsif ( $ch =~ /[[:ascii:]]/ ) {
            form_driver( $cform, ord($ch) );
        }
        else {
            beep();
        }
    }
    unpost_form($cform);
    del_panel($panel);
    delwin($win);
    free_form($cform);
    $strbuff = field_buffer( $fp[1], 0 );
    $strbuff =~ s/\s+$//;
    map { free_field($_) } @fp;
    @fp   = ();
    @fset = ();
    curs_set($OFF) if $ctx->{cfg}{HIDE_CURSOR};
    return ( $es, $strbuff );
}

sub disp_page {
    my ( $win, $n, $tot, $caller, $screen_name ) = @_;

    my ( $saveY, $saveX, $buff, $pos, $obj, $ovl_flag );

    getyx( $win, $saveY, $saveX );
    $n = "0$n" if ( $tot > 9  and $n < 10 );
    $n = "0$n" if ( $tot > 99 and $n < 10 );
    if ( $caller eq 'browser' or $caller eq 'form' ) {
        $obj = 'Pg';
    }
    else {
        $obj = 'Op';
    }
    if ( $caller eq 'form' ) {
        $ovl_flag = $ovl_mode ? 'Ovl' : 'Ins';
    }
    else {
        $ovl_flag = '';
    }
    $pos         = "$obj:$n/$tot";
    $screen_name = basename($screen_name) if $screen_name;
    $buff        = sprintf( "%s %3s %s",
        $ctx->{cfg}{SHOW_SCREEN_NAME} ? $screen_name : '',
        $ovl_flag, $pos );
    addstr( $win, 0, $COLS - length($buff), $buff );
    chgat( $win, 0, $COLS - length($pos) - 4, 3, A_REVERSE, 0, 0 )
      if $ovl_flag and $ctx->{cfg}{LAYOUT} == $NORMAL;
    move( $win, $saveY, $saveX );
}

sub load_menu {
    my ( $name, $menu ) = @_;    # $menu: caller's hashref to fill (M7 Phase 2)

    my ( $key, $val, $text, $found, $ic, $res );
    my @lines;

    $found = $NO;
    for my $dir (@mf_path) {
        my $fname = "$dir/$name$MENUEXT";
        trace( "looking for $fname", $LOG_SCAN_PATHS );
        if ( -e $fname ) {
            $found = $YES;
            if ( -d $fname ) {
                trace("load dynamic menu $fname");
                @flist = glob("$fname/$DMENU_DEF_FNAME $fname/*.item");
            }
            else {
                trace("load static menu $fname");
                @flist = ($fname);
            }
            %{$menu} = ();
            $res = $ES_NO_ERR;

            foreach my $fname (@flist) {
                if ( open( INF, $fname ) ) {
                    push @lines, $_ while (<INF>);
                    close(INF);
                }
                elsif ( $fname !~ /$DMENU_DEF_FNAME$/ ) {
                    $res = $ES_FOPEN_ERR;
                }
            }

            $ic = 0;
            if ( $res == $ES_NO_ERR ) {
                for ( my $i = 0 ; $i <= $#lines ; $i++ ) {
                    splice @lines, $i--, 1 if $lines[$i] =~ /^\s*#/;
                }
                $text = join( '', @lines );

                # The bracket parser is now a pure module (CCFE::MenuFile);
                # load_menu keeps the file finding/reading, fills the caller's
                # %menu hashref (M7 Phase 2) and applies the remaining side
                # effects -- $ctx->{state}{SCREEN_DIR} and the default top message.
                my ( $parsed, $pstatus, $warns );
                ( $parsed, $pstatus, $warns, $ic ) =
                  CCFE::MenuFile::parse($text);
                %{$menu} = %{$parsed};
                trace($_) for @{$warns};
                $res = $ES_SYNTAX_ERR if $pstatus eq 'syntax_error';
                if ( $res == $ES_NO_ERR ) {
                    @{ $menu->{top} } = @MENU_TOP_MSG unless @{ $menu->{top} };
                    $ctx->{state}{SCREEN_DIR} = $dir;
                    $$path      = $dir;
                }
            }
            else {
                trace("error opening $fname: $!");
                $res = $ES_FOPEN_ERR;
            }
            trace("found $ic menu item(s)");
            $res = $ES_NO_ITEMS if $ic < 1;
            last;
        }
    }
    unless ($found) {
        trace("menu \"$name\" NOT FOUND!");
        $res = $ES_NOT_FOUND;
    }
    return $res;
}

sub load_form {
    my ( $name, $path, $form ) = @_;    # $form: caller's hashref to fill

    # M7 Phase 3: build into a lexical %form and copy it out to the caller's
    # ref at the end, so the ~30 `$form{...}` sites below stay byte-identical
    # rather than the global they used to fill.
    my %form;
    my ( $key, $val, $found, $text, $fc, $res );
    my @lines;

    $found = $NO;
    for my $dir (@mf_path) {
        my $fname = "$dir/$name$FORMEXT";
        trace( "looking for $fname", $LOG_SCAN_PATHS );
        if ( -f $fname ) {
            $found = $YES;
            trace("load $fname");
            %form = ();
            undef %form;
            $res = $ES_NO_ERR;
            if ( open( INF, $fname ) ) {
                while (<INF>) {
                    next if /^\s*#/;
                    push @lines, $_;
                }
                close(INF);
                $text = join( '', @lines );

                # The bracket-block parse now lives in the pure CCFE::FormFile
                # module (ROADMAP M7): it returns a plain data structure with no
                # terminal/global side effects.  load_form keeps the effectful
                # rest -- command/boolean defaults, the $COLS-dependent separator
                # formatting, select-item resolution -- below.
                my ( $parsed, $pstatus, $warns, $fcount ) =
                  CCFE::FormFile::parse(
                    $text,
                    {
                        bool      => \%bool_vals,
                        type      => \%type_vals,
                        sep_type  => \%sep_type_vals,
                        separator => $SEPARATOR,
                        no        => $NO,
                    }
                  );
                %form = %{$parsed};
                trace($_) for @{$warns};
                $fc  = $fcount;
                $res = $ES_SYNTAX_ERR if $pstatus eq 'syntax_error';
                if ( $res == $ES_NO_ERR ) {
                    @{ $form{top} } = @FORM_TOP_MSG unless @{ $form{top} };

                    # Separator label formatting depends on $COLS, so the pure
                    # parser defers it to here: centre the text, or draw a rule
                    # line across the field area.
                    # Clamp to >= 0: headless paths (--dump/-k) run before
                    # initscr, so $COLS is 0 and the width goes negative; a
                    # negative `x` repeat is an empty string either way.
                    my $line_width = $COLS - $FIELD_LMARGIN - $FIELD_RMARGIN;
                    $line_width = 0 if $line_width < 0;
                    foreach my $f ( @{ $form{fields} } ) {
                        next unless ( $f->{type} // 0 ) == $SEPARATOR;
                        next unless defined $f->{sep_type};
                        if ( $f->{sep_type} == $SEP_TEXT_CENTER ) {
                            my $lblanks =
                              ( $line_width - length( $f->{label} ) ) / 2;
                            $lblanks = 0 if $lblanks < 0;
                            $f->{label} =
                              sprintf( "%s%s", ' ' x ($lblanks), $f->{label} );
                        }
                        elsif ( $f->{sep_type} == $SEP_LINE ) {
                            $f->{label} = '-' x $line_width;
                        }
                        elsif ( $f->{sep_type} == $SEP_LINE_DOUBLE ) {
                            $f->{label} = '=' x $line_width;
                        }
                    }

                    foreach my $i ( 0 .. $#{ $form{fields} } ) {
                        my $id      = $form{fields}[$i]{id};
                        my $type    = $form{fields}[$i]{type};
                        my $val     = '';
                        my $default = '';
                        if ( $form{fields}[$i]{default} ) {
                            my ( $datatype, $data ) = split /:/,
                              $form{fields}[$i]{default}, 2;
                          SWITCH: {
                                $_ = lc $datatype;
                                if (/^const$/) {
                                    $default = $data;
                                    last SWITCH;
                                }
                                if (/^command$/) {

                                    trace(
"set default value field ID \"$id\" with cmd \"$data\"",
                                        $LOG_DEFAULT_CMD
                                    );
                                    my @res = ();
                                    my @err = ();
                                    unless (
                                        exec_command(
                                            $data, $form{path},
                                            \@res, \@err
                                        )
                                      )
                                    {
                                        trace( "error:\n" . join( '', @err ),
                                            $LOG_DEFAULT_CMD );
                                        @res = ('ERROR!');
                                    }
                                    $default = join( ' ', @res );

                                    last SWITCH;
                                }
                                $default = 'ERROR!';
                            }
                            if ( $type & $BOOLEAN ) {
                                my @vals = ();
                                @vals = ( $BFIELD_YES, $BFIELD_NO )
                                  if $type == $BOOLEAN;
                                @vals =
                                  ( $BFIELD_NULL, $BFIELD_YES, $BFIELD_NO )
                                  if $type == $NULLBOOLEAN;
                                $default =~ s/\s+$//;
                                $default =~ s/^\s+//;
                                unless ( in( uc($default), @vals ) ) {
                                    trace(
"wrong default value \"$default\" in (NULL)BOOLEAN in field ID $form{fields}[$i]{id}"
                                    );
                                    $default = 'ERROR!';
                                }
                                $default =
                                  uc( ralign( $default, $BOOLEAN_FIELD_SIZE ) );
                            }
                        }
                        elsif ( $type & $BOOLEAN ) {
                            $default =
                              ralign( $BFIELD_DEFAULT, $BOOLEAN_FIELD_SIZE );
                        }
                        $form{fields}[$i]{default} = $default;

                        if ( $type & $BOOLEAN ) {
                            $form{fields}[$i]{len} = $BOOLEAN_FIELD_SIZE;
                        }

                        unless ( defined( $form{fields}[$i]{type} ) ) {
                            $form{fields}[$i]{type} = $STRING;
                        }
                        unless ( defined( $form{fields}[$i]{len} ) ) {
                            $form{fields}[$i]{len} = 20;
                        }
                        unless ( defined( $form{fields}[$i]{enabled} ) ) {
                            $form{fields}[$i]{enabled} = $YES;
                        }
                        unless ( defined( $form{fields}[$i]{htab} ) ) {
                            $form{fields}[$i]{htab} = 0;
                        }
                        unless ( defined( $form{fields}[$i]{vtab} ) ) {
                            $form{fields}[$i]{vtab} = 0;
                        }
                        unless ( defined( $form{fields}[$i]{hidden} ) ) {
                            $form{fields}[$i]{hidden} = $NO;
                        }
                        unless ( defined( $form{fields}[$i]{ignore_unchgd} ) ) {
                            $form{fields}[$i]{ignore_unchgd} = $NO;
                        }
                        unless ( defined( $form{fields}[$i]{list_sep} ) ) {
                            $form{fields}[$i]{list_sep} = ' ';
                        }
                        $form{fields}[$i]{changed} = $NO;
                        $form{fields}[$i]{valueFg} = $ctx->{cfg}{valueFg};
                        $form{fields}[$i]{valueBg} = $ctx->{cfg}{valueBg};

                        if ( $type == $BOOLEAN ) {
                            $form{fields}[$i]{list_cmd} =
"const:single-val:\"$BFIELD_YES $BFIELD_YES_DESCR\",\"$BFIELD_NO $BFIELD_NO_DESCR\"";
                        }
                        if ( $type == $NULLBOOLEAN ) {
                            $form{fields}[$i]{list_cmd} =
"const:single-val:\"$BFIELD_YES $BFIELD_YES_DESCR\",\"$BFIELD_NO $BFIELD_NO_DESCR\",\"$BFIELD_NULL $BFIELD_NULL_DESCR\"";
                        }
                    }

                    ( $val, undef, $key ) =
                      extract_bracketed( $form{action}, '{',
                        '\s*select\-item+\s*' );
                    if ($key) {
                        my $id;
                        $val =~ s/^\{\s*//;
                        $val =~ s/\s*\n?\s*\}$//;
                        foreach $choice ( split /\n/, $val ) {
                            $choice =~ /^\s*(\w+)\s*:\s*(.+)\s*$/;
                            $id = $1;
                            $form{action} = $2;
                            last if ( $id eq $ctx->{state}{last_item_id} );
                        }
                        if ( $id ne $ctx->{state}{last_item_id} ) {
                            trace("ERROR: select-item with unknown item ID\n");
                            $form{action} = '';
                        }
                    }

                    $ctx->{state}{SCREEN_DIR} = $dir;
                    $$path      = $dir;
                }
            }
            else {
                trace("error opening $name: $!");
                $res = $ES_FOPEN_ERR;
            }
            trace("found $fc form field(s)");
            last;
        }
    }
    unless ($found) {
        trace("form \"$name\" NOT FOUND!");
        $res = $ES_NOT_FOUND;
    }

    # Hand the built form to the caller (M7 Phase 3).  The {fields} arrayref is
    # shared by this shallow copy, so the caller owns the same field hashes.
    %{$form} = %form if $form;
    return $res;
}

# TD-3: the colour/attribute settings in the field_attr{} / active_field_attr{}
# / menu_global{} / browser_global{} config sections were ~20 copies of the same
# one-line idiom -- look up a config key, parse its value with attr_value(),
# keep the previous value when the parse fails.  These maps drive that
# uniformly: the (upper-cased) config attribute name -> the $ctx->{cfg} key it
# sets.  field_attr and active_field_attr share the same attribute names but
# target different cfg keys, hence the two separate maps.
my %FIELD_ATTR_MAP = (
    LABEL_FG         => 'labelFg',
    LABEL_BG         => 'labelBg',
    VALUE_FG         => 'valueFg',
    VALUE_BG         => 'valueBg',
    CHANGED_VALUE_FG => 'cf_valueFg',
    CHANGED_VALUE_BG => 'cf_valueBg',
);
my %ACTIVE_FIELD_ATTR_MAP = (
    LABEL_FG         => 'af_labelFg',
    LABEL_BG         => 'af_labelBg',
    VALUE_FG         => 'af_valueFg',
    VALUE_BG         => 'af_valueBg',
    CHANGED_VALUE_FG => 'acf_valueFg',
    CHANGED_VALUE_BG => 'acf_valueBg',
);
my %MENU_ATTR_MAP = (
    SCREEN_ATTR   => 'MENU_SCREEN_ATTR',
    ITEM_ATTR     => 'MENU_ITEM_ATTR',
    SELECTED_ATTR => 'MENU_SEL_ATTR',
    TITLE_ATTR    => 'TITLE_ATTR',
    KEY_ATTR      => 'KEY_ATTR',
);
my %BROWSER_ATTR_MAP = (
    INFO_ATTR   => 'RS_INFO_ATTR',
    STDERR_ATTR => 'RS_STDERR_ATTR',
    STDOUT_ATTR => 'RS_STDOUT_ATTR',
);

# Apply a whole field_attr{} / active_field_attr{} section: every line is a
# colour key from $map, parsed by attr_value() (a bad value keeps the previous
# setting).  An unrecognised key is a syntax error, mirroring the old
# per-section else-arm.  $key is the section name (for the message); $res_ref
# receives $ES_SYNTAX_ERR on a bad key.
sub apply_attr_section ( $val, $map, $key, $res_ref ) {
    for my $line ( split /\s*\n\s*/, $val ) {
        my ( $attrk, $attrv ) = split /\s*=\s*/, $line;
        if ( my $cfgkey = $map->{ uc( $attrk // '' ) } ) {
            $ctx->{cfg}{$cfgkey} = attr_value($attrv) // $ctx->{cfg}{$cfgkey};
        }
        else {
            trace(
                "unknown parameter \"$attrk\" in configuration section ${key}\{\}"
            );
            ${$res_ref} = $ES_SYNTAX_ERR;
        }
    }
    return;
}

sub load_config {
    my ( $key, $val, $text, $found, $res, $fname );
    my @lines;

    $found = $NO;
    for $fname (@cnf_path) {
        trace( "looking for $fname", $LOG_SCAN_PATHS );
        if ( -f $fname ) {
            # TD-1a: once RESTRICTED is on, a user-writable config file is
            # untrusted -- skip it, so a user cannot weaken the policy (turn
            # restricted off, widen the allowlist, change the shell/path) from
            # ~/.config or ~/.ccfe.  System (non-user-writable) files still
            # apply, in the system->user->legacy order, so the system config
            # that sets `restricted = yes` locks out the later user files.
            if ( $ctx->{cfg}{RESTRICTED} and -w $fname ) {
                trace("RESTRICTED: ignoring user-writable config \"$fname\"");
                next;
            }
            @lines = ();
            $found = $YES;
            trace("load $fname");
            $res = $ES_NO_ERR;
            if ( open( INF, $fname ) ) {
                while (<INF>) {
                    next if /^\s*#/;
                    push @lines, $_;
                }
                close(INF);
                @lines = map { s/\s*#.*\n/\n/; $_ } @lines;
                $text = join( '', @lines );

                my $term = uc $ENV{TERM};

                # The top-level `SECTION { ... }` walk now lives in the pure
                # CCFE::Config tokenizer (ROADMAP M7).  The (effectful,
                # scope-bound) per-section dispatch below -- including the
                # `eval "$VAR = ..."` colour/attribute assignments and the
                # term-/$COLS-dependent handling -- stays here.
                my ( $sections, $cstatus ) = CCFE::Config::parse($text);
                foreach my $sec ( @{$sections} ) {
                    $key = $sec->{name};
                    $val = $sec->{body};
                  SWITCH: {
                        $_ = uc $key;
                        if (/^GLOBAL$/) {
                            my $s;
                            my @finfo = split /\s*\n\s*/, $val;
                            foreach $s (@finfo) {
                                ( $attrk, $attrv ) = split /\s*=\s*/, $s, 2;
                              ASWITCH: {
                                    $_ = uc $attrk;
                                    if (/^SCREEN_LAYOUT$/) {
                                        if (
                                            defined(
                                                $layout_vals{ lc($attrv) }
                                            )
                                          )
                                        {
                                            $ctx->{cfg}{LAYOUT} =
                                              $layout_vals{ lc($attrv) };
                                        }
                                        else {
                                            trace(
"wrong value \"$attrv\" for \"$attrk\" attribute"
                                            );
                                            $res = $ES_SYNTAX_ERR;
                                        }
                                        last ASWITCH;
                                    }
                                    elsif (/^HIDE_CURSOR$/) {
                                        if (
                                            defined( $bool_vals{ lc($attrv) } )
                                          )
                                        {
                                            $ctx->{cfg}{HIDE_CURSOR} =
                                              $bool_vals{ lc($attrv) };
                                        }
                                        else {
                                            trace(
"wrong value \"$attrv\" for \"$attrk\" attribute"
                                            );
                                            $res = $ES_SYNTAX_ERR;
                                        }
                                        last ASWITCH;
                                    }
                                    elsif (/^MOUSE$/) {
                                        if (
                                            defined( $bool_vals{ lc($attrv) } )
                                          )
                                        {
                                            $ctx->{cfg}{ENABLE_MOUSE} =
                                              $bool_vals{ lc($attrv) };
                                        }
                                        else {
                                            trace(
"wrong value \"$attrv\" for \"$attrk\" attribute"
                                            );
                                            $res = $ES_SYNTAX_ERR;
                                        }
                                        last ASWITCH;
                                    }
                                    elsif (/^SHOW_SCREEN_NAME$/) {
                                        if (
                                            defined( $bool_vals{ lc($attrv) } )
                                          )
                                        {
                                            $ctx->{cfg}{SHOW_SCREEN_NAME} =
                                              $bool_vals{ lc($attrv) };
                                        }
                                        else {
                                            trace(
"wrong value \"$attrv\" for \"$attrk\" attribute"
                                            );
                                            $res = $ES_SYNTAX_ERR;
                                        }
                                        last ASWITCH;
                                    }
                                    elsif (/^PATH$/) {
                                        $ctx->{cfg}{PATH} = $attrv;
                                        last ASWITCH;
                                    }
                                    elsif (/^LOG_LEVEL$/) {
                                        $ctx->{cfg}{LOG_LEVEL} = $attrv;
                                        $ctx->{cfg}{LOG_FNAME} = '' if $ctx->{cfg}{LOG_LEVEL} == 0;
                                        last ASWITCH;
                                    }
                                    elsif (/^PERMIT_DEBUG$/) {
                                        if (
                                            defined( $bool_vals{ lc($attrv) } )
                                          )
                                        {
                                            $ctx->{cfg}{PERMIT_DEBUG} =
                                              $bool_vals{ lc($attrv) };
                                        }
                                        else {
                                            trace(
"wrong value \"$attrv\" for \"$attrk\" attribute"
                                            );
                                            $res = $ES_SYNTAX_ERR;
                                        }
                                        last ASWITCH;
                                    }
                                    elsif (/^SHELL$/) {
                                        $ctx->{cfg}{OPEN3_SHELL} = $attrv;
                                        last ASWITCH;
                                    }
                                    elsif (/^USER_SHELL$/) {
                                        $ctx->{cfg}{USER_SHELL} = $attrv;
                                        last ASWITCH;
                                    }
                                    elsif (/^RESTRICTED$/) {
                                        if (
                                            defined( $bool_vals{ lc($attrv) } )
                                          )
                                        {
                                            $ctx->{cfg}{RESTRICTED} =
                                              $bool_vals{ lc($attrv) };
                                        }
                                        else {
                                            trace(
"wrong value \"$attrv\" for \"$attrk\" attribute"
                                            );
                                            $res = $ES_SYNTAX_ERR;
                                        }
                                        last ASWITCH;
                                    }
                                    elsif (/^RESTRICTED_ALLOW$/) {
                                        push @{ $ctx->{cfg}{RESTRICTED_ALLOW} },
                                          split /\s*,\s*/, $attrv;
                                        last ASWITCH;
                                    }
                                    elsif (/^LOAD_USER_OBJECTS$/) {
                                        if (
                                            defined( $bool_vals{ lc($attrv) } )
                                          )
                                        {
                                            if ( $bool_vals{ lc($attrv) } ) {

                                                # v2 searches the user dirs by
                                                # default; kept so existing
                                                # configs still parse.
                                                push @mf_path,
                                                  "$USR_OBJ/$CALLNAME",
                                                  "$LEGACY_DIR/$CALLNAME";
                                                push @cnf_path,
                                                  "$USR_CFG/$CALLNAME.conf",
                                                  "$LEGACY_DIR/$CALLNAME.conf";
                                            }
                                        }
                                        else {
                                            trace(
"wrong value \"$attrv\" for \"$attrk\" attribute"
                                            );
                                            $res = $ES_SYNTAX_ERR;
                                        }
                                        last ASWITCH;
                                    }
                                    elsif (/^KEY_F([0-9]{1,2})$/) {
                                        if ( $1 >= 1 and $1 <= 12 ) {
                                            if (
                                                in(
                                                    lc($attrv),
                                                    @fn_key_functions
                                                )
                                              )
                                            {
                                                $ctx->{cfg}{keys}{ lc($attrv) }{code} =
                                                  KEY_F($1);
                                                $ctx->{cfg}{keys}{ lc($attrv) }{key} =
                                                  "F$1";
                                                $ctx->{cfg}{keys}{ lc($attrv) }{label} =
                                                  eval "\$KEY_F$1_LABEL";
                                            }
                                            else {
                                                trace(
"unknown function ID \"$attrv\" for \"$attrk\" attribute"
                                                );
                                            }
                                        }
                                        else {
                                            trace(
"trying to configure invalid key \"F$1\""
                                            );
                                        }
                                        last ASWITCH;
                                    }
                                    else {
                                        trace(
"unknown configuration parameter \"$attrk\""
                                        );
                                        $res = $ES_SYNTAX_ERR;
                                    }
                                }
                            }
                            last SWITCH;
                        }
                        elsif (/^BROWSER_GLOBAL$/) {
                            my $gs = lc($_);
                            my $s;
                            my @finfo = split /\s*\n\s*/, $val;
                            foreach $s (@finfo) {
                                ( $attrk, $attrv ) = split /\s*=\s*/, $s;
                              ASWITCH: {
                                    $_ = uc $attrk;
                                    if (/^MAX_ROWS$/) {
                                        $ctx->{cfg}{MAX_PAD_LINES} = $attrv;
                                        last ASWITCH;
                                    }
                                    if ( my $cfgkey = $BROWSER_ATTR_MAP{$_} ) {
                                        $ctx->{cfg}{$cfgkey} = attr_value($attrv) // $ctx->{cfg}{$cfgkey};
                                        last ASWITCH;
                                    }
                                    if (/^FNKEYS_ROWS$/) {
                                        $ctx->{cfg}{RS_FOOTER_ROWS} = 1 + $attrv;
                                        last ASWITCH;
                                    }
                                    if (/^END_MARKER$/) {
                                        if ( $ctx->{cfg}{END_MARKER} =
                                            substr( $attrv, 0, $COLS ) )
                                        {
                                            my $filler =
                                              ' ' x
                                              int(
                                                ( $COLS - length($ctx->{cfg}{END_MARKER}) )
                                                / 2 );
                                            $ctx->{cfg}{END_MARKER} =
                                              "$filler$ctx->{cfg}{END_MARKER}$filler"
                                              . (
                                                length($out) < $COLS
                                                ? ' '
                                                : '' );
                                        }
                                        last ASWITCH;
                                    }
                                    else {
                                        trace(
"$gs: unknown parameter \"$attrk\" in configuration section $key\{\}"
                                        );
                                        $res = $ES_SYNTAX_ERR;
                                    }
                                }
                            }
                            last SWITCH;
                        }
                        elsif (/^FORM_GLOBAL$/) {
                            my $gs = lc($_);
                            my $s;
                            my @finfo = split /\s*\n\s*/, $val;
                            foreach $s (@finfo) {
                                ( $attrk, $attrv ) = split /\s*=\s*/, $s;
                              ASWITCH: {
                                    $_ = uc $attrk;
                                    if (   /^FIELD_PAD$/
                                        or /^FIELD_PAD.\Q$term\E$/ )
                                    {
                                        if ( $attrv =~ /"(.)"/ ) {
                                            $ctx->{cfg}{FIELD_PAD} = ord($1);
                                        }
                                        else {
                                            trace(
"$gs: syntax error \"$attrv\" in \"$attrk\" attribute"
                                            );
                                            $res = $ES_SYNTAX_ERR;
                                        }
                                        last ASWITCH;
                                    }
                                    elsif (/^HIDDEN_FIELD_PAD$/) {
                                        if ( $attrv =~ /"(.)"/ ) {
                                            $ctx->{cfg}{HFIELD_PAD} = ord($1);
                                        }
                                        else {
                                            trace(
"$gs: syntax error \"$attrv\" in \"$attrk\" attribute"
                                            );
                                            $res = $ES_SYNTAX_ERR;
                                        }
                                        last ASWITCH;
                                    }
                                    elsif (/^SHOW_CHANGED_FIELDS$/) {
                                        if (
                                            defined( $bool_vals{ lc($attrv) } )
                                          )
                                        {
                                            $ctx->{cfg}{SHOW_CHGD_FIELDS} =
                                              $bool_vals{ lc($attrv) };
                                        }
                                        else {
                                            trace(
"$gs: wrong value \"$attrv\" for \"$attrk\" attribute"
                                            );
                                            $res = $ES_SYNTAX_ERR;
                                        }
                                        last ASWITCH;
                                    }
                                    elsif (/^SHOW_FIELD_FLAGS$/) {
                                        if (
                                            defined( $bool_vals{ lc($attrv) } )
                                          )
                                        {
                                            $ctx->{cfg}{SHOW_FIELD_FLAGS} =
                                              $bool_vals{ lc($attrv) };
                                        }
                                        else {
                                            trace(
"$gs: wrong value \"$attrv\" for \"$attrk\" attribute"
                                            );
                                            $res = $ES_SYNTAX_ERR;
                                        }
                                        last ASWITCH;
                                    }
                                    elsif (/^SHOW_DOTS$/) {
                                        if (
                                            defined( $bool_vals{ lc($attrv) } )
                                          )
                                        {
                                            $ctx->{cfg}{SHOW_DOTS} =
                                              $bool_vals{ lc($attrv) };
                                        }
                                        else {
                                            trace(
"$gs: wrong value \"$attrv\" for \"$attrk\" attribute"
                                            );
                                            $res = $ES_SYNTAX_ERR;
                                        }
                                        last ASWITCH;
                                    }
                                    elsif (/^INITIAL_OVL_MODE$/) {
                                        if (
                                            defined( $bool_vals{ lc($attrv) } )
                                          )
                                        {
                                            $ctx->{cfg}{INITIAL_OVL_MODE} =
                                              $bool_vals{ lc($attrv) };
                                        }
                                        else {
                                            trace(
"$gs: wrong value \"$attrv\" for \"$attrk\" attribute"
                                            );
                                            $res = $ES_SYNTAX_ERR;
                                        }
                                        last ASWITCH;
                                    }
                                    elsif (/^VALUE_DELIMITERS$/) {
                                        if ( $attrv =~ /"(.)"\s*,\s*"(.)"/ ) {
                                            $ctx->{cfg}{fval_delim} = [ $1, $2 ];
                                        }
                                        else {
                                            trace(
"$gs: syntax error \"$attrv\" in \"$attrk\" attribute"
                                            );
                                            $res = $ES_SYNTAX_ERR;
                                        }
                                        last ASWITCH;
                                    }
                                    elsif (/^FIELD_VALUE_POS$/) {
                                        if (    $attrv =~ /^-*[0-9]+$/
                                            and $attrv >= -1 )
                                        {
                                            $ctx->{cfg}{FIELD_VALUE_POS} = $attrv;
                                        }
                                        else {
                                            trace(
"$gs: syntax error \"$attrv\" in \"$attrk\" attribute (number >= -1 expected)"
                                            );
                                            $res = $ES_SYNTAX_ERR;
                                        }
                                        last ASWITCH;
                                    }
                                    elsif (/^FNKEYS_ROWS$/) {
                                        $ctx->{cfg}{FS_FOOTER_ROWS} = 1 + $attrv;
                                        last ASWITCH;
                                    }
                                    else {
                                        trace(
"$gs: unknown configuration parameter \"$attrk\""
                                        );
                                        $res = $ES_SYNTAX_ERR;
                                    }
                                }
                            }
                            last SWITCH;
                        }
                        elsif ( /^FIELD_ATTR$/ or /^FIELD_ATTR.\Q$term\E$/ ) {
                            apply_attr_section( $val, \%FIELD_ATTR_MAP, $key,
                                \$res );
                            last SWITCH;
                        }
                        elsif (/^ACTIVE_FIELD_ATTR$/
                            or /^ACTIVE_FIELD_ATTR.\Q$term\E$/ )
                        {
                            apply_attr_section( $val, \%ACTIVE_FIELD_ATTR_MAP,
                                $key, \$res );
                            last SWITCH;
                        }
                        elsif (/^MENU_GLOBAL$/) {
                            my $gs = lc($_);
                            my $s;
                            my @finfo = split /\s*\n\s*/, $val;
                            foreach $s (@finfo) {
                                ( $attrk, $attrv ) = split /\s*=\s*/, $s;
                              ASWITCH: {
                                    $_ = uc $attrk;
                                    if (/^MARK_NOACTION_ITEMS$/) {
                                        if (
                                            defined( $bool_vals{ lc($attrv) } )
                                          )
                                        {
                                            $ctx->{cfg}{MARK_NOACT_ITEMS} =
                                              $bool_vals{ lc($attrv) };
                                        }
                                        else {
                                            trace(
"$gs: wrong value \"$attrv\" for \"$attrk\" attribute"
                                            );
                                            $res = $ES_SYNTAX_ERR;
                                        }
                                        last ASWITCH;
                                    }
                                    if (/^FNKEYS_ROWS$/) {
                                        $ctx->{cfg}{MS_FOOTER_ROWS} = 1 + $attrv;
                                        last ASWITCH;
                                    }
                                    if ( my $cfgkey = $MENU_ATTR_MAP{$_} ) {
                                        $ctx->{cfg}{$cfgkey} = attr_value($attrv) // $ctx->{cfg}{$cfgkey};
                                        last ASWITCH;
                                    }
                                    else {
                                        trace(
"$gs: unknown parameter \"$attrk\" in configuration section $key\{\}"
                                        );
                                        $res = $ES_SYNTAX_ERR;
                                    }
                                }
                            }
                            last SWITCH;
                        }
                        else {
                            trace("unknown configuration parameter \"$key\"");
                            $res = $ES_SYNTAX_ERR;
                        }
                    }
                }
                $res = $ES_SYNTAX_ERR if $cstatus eq 'syntax_error';
            }
            else {
                trace("error opening $fname: $!");
                $res = $ES_FOPEN_ERR;
            }
        }
        unless ($found) {
            trace("configuration file \"$fname\" NOT FOUND!");
            $res = $ES_NOT_FOUND;
        }
    }
    return $res;
}

# Apply an action's options (confirm / log / wait_key), shared by do_menu and
# do_form (TD-3 de-dup).  Sets the global $LOG_REQUESTED; `confirm` pops a
# Yes/No list titled $title.  Returns ($wait_key, $aborted, $es): $aborted is
# true when the user declined the confirmation, and $es is the confirmation
# list's status (undef when there was no `confirm` option) so the caller can
# honour an exit from that dialog.
sub apply_action_opts {
    my ( $opts, $win, $title ) = @_;
    my $wait_key = $NO;
    my $aborted  = $NO;
    my $es;
    $LOG_REQUESTED = $NO;
    for my $opt ( @{$opts} ) {
        if ( $opt eq 'confirm' ) {
            my $val;
            ( $es, $val ) =
              do_list( $win, $title, 'single-val', \@CONFIRM_ITEMS, undef );
            $aborted = $YES if $val ne $BFIELD_YES;
        }
        elsif ( $opt eq 'log' )      { $LOG_REQUESTED = $YES }
        elsif ( $opt eq 'wait_key' ) { $wait_key      = $YES }
        else                         { trace("unknown action option \"$opt\"") }
    }
    return ( $wait_key, $aborted, $es );
}

sub do_menu {
    my ( $menuname, $title ) = @_;

    my @fset;
    my ( $cmenu, $es, $rows, $cols, $i, $ci, $item, $ch, $mlmargin, $msub );
    my ( $action, $args, $wait_key );
    my @actopts;
    my ($pan);
    my ( $win,     $mwinr );
    my ( $exit_id, $exit_descr );
    my ( $pos_msg, $saveY, $saveX );

    # M7 de-globalisation (Phase 2): the menu is a per-call lexical filled by
    # load_menu, not a `local` global -- the anonymous draw/resize closures
    # below capture it correctly, and a nested do_menu gets its own.
    my %menu;

    unless ( $es = load_menu( $menuname, \%menu ) ) {
        foreach $i ( 0 .. $#{ $menu{items} } ) {
            if ( $ctx->{cfg}{MARK_NOACT_ITEMS} and !$menu{items}[$i]{action} ) {
                $menu{items}[$i]{descr} = "($menu{items}[$i]{descr})";
            }
            if ( $ctx->{cfg}{LAYOUT} != $SIMPLE ) {
                $menu{items}[$i]{descr} = " $menu{items}[$i]{descr} ";
            }
            $item = new_item( $menu{items}[$i]{descr}, "" );

            if ( $item eq '' ) {
                fatal("new_item($menu{items}[$i]{descr}) failed: $item");
            }
            $menu{items}[$i]{ptr} = $item;
            push @fset, ${$item};
        }
        push @fset, 0;

        # new_menu() keeps this pointer WITHOUT copying the array (documented
        # ncurses behaviour: the items array must stay valid for the life of
        # the menu).  Passing an inline `pack 'L!*'` temporary left ncurses
        # holding a dangling pointer; on small menus (1-2 items) the freed
        # Perl buffer was reused immediately, so the first menu operation
        # segfaulted -- this crashed the demo/ccfe menus on startup.  Keeping
        # the buffer in a lexical that lives until free_menu() below fixes it.
        # Regression-guarded by t/03-tty-smoke.t.
        my $items_buf = pack 'L!*', @fset;
        $cmenu = new_menu($items_buf);
        if ( $cmenu eq '' ) { fatal("do_menu.new_menu() failed") }

        set_menu_mark( $cmenu, ' ' );
        set_menu_fore( $cmenu, $ctx->{cfg}{MENU_SEL_ATTR} );
        set_menu_back( $cmenu, $ctx->{cfg}{MENU_ITEM_ATTR} );
        $title = $menu{title} if $menu{title};

        # Build (and, on KEY_RESIZE, rebuild) the windows and menu geometry at
        # the current $LINES/$COLS.  A closure over do_menu's lexicals, so the
        # layout can be re-run for a terminal resize without duplicating it.
        my $draw_menu = sub {
            # Never build below the layout's minimum (80x24): ncurses clips the
            # oversize window to a smaller terminal, and this keeps sub-window
            # creation valid so a tiny terminal cannot crash us.
            my $eff_lines = $LINES < 24 ? 24 : $LINES;
            my $eff_cols  = $COLS < 80  ? 80 : $COLS;
            $mwinr =
              $eff_lines -
              ( $MS_HEADER_ROWS + $MS_TOP_ROWS + $MS_BOTTOM_ROWS
                  + $ctx->{cfg}{MS_FOOTER_ROWS} );
            $win = newwin( $eff_lines, $eff_cols, 0, 0 );
            $pan = new_panel($win);
            bkgd( $win, $ctx->{cfg}{MENU_SCREEN_ATTR} );
            set_menu_format( $cmenu, $mwinr, 1 );
            scale_menu( $cmenu, $rows, $cols );
            $mlmargin = int( ( $eff_cols - $cols ) / 2 );
            $mlmargin = 1 if ( $ctx->{cfg}{LAYOUT} == $SIMPLE );
            $mlmargin = 0 if $mlmargin < 0;
            $msub =
              derwin( $win, $rows, $cols, $MS_HEADER_ROWS + $MS_TOP_ROWS,
                $mlmargin );
            set_menu_win( $cmenu, $win );
            set_menu_sub( $cmenu, $msub );
            bkgd( $msub, $ctx->{cfg}{MENU_SCREEN_ATTR} );
            keypad( $win, $ON );
            clear($win);
            init_title( $win, $MS_HEADER_ROWS, $title );
            init_top( $win, $NO, $MS_HEADER_ROWS, $MS_TOP_ROWS,
                @{ $menu{top} } );
            init_footer( $win, $NO, $ctx->{cfg}{MS_FOOTER_ROWS}, @MSKeys );
            post_menu($cmenu);
            refresh($win);
        };
        $draw_menu->();

        $es = 0;
        while ( !defined($ctx->{state}{exec_args}) ) {
            disp_page( $win, item_index( current_item($cmenu) ) + 1,
                item_count($cmenu), 'menu', $menuname );

            $ch = getch($win);
            if ( $MOUSE_ON and $ch == KEY_MOUSE ) {
                # Point at a menu item: a left click moves the selection to the
                # clicked row; a double click also activates it (re-dispatched
                # as Enter, below).  Clicks outside the item rows are ignored.
                # getmouse() fills a packed MEVENT { short id; int x,y,z;
                # mmask_t bstate } -- we need the event row and the buttons.
                my $activate = $NO;
                my $mev      = '';
                if ( getmouse($mev) == OK and length($mev) >= 20 ) {
                    my $my = ( unpack( 'x4 l2', $mev ) )[1];
                    my $mb =
                      length($mev) >= 24
                      ? unpack( 'x16 L!', $mev )
                      : unpack( 'x16 V', $mev );
                    my $row = $my - ( $MS_HEADER_ROWS + $MS_TOP_ROWS );
                    my $t   = top_row($cmenu) + $row;
                    if (    $row >= 0
                        and $row < $rows
                        and $t >= 0
                        and $t < item_count($cmenu) )
                    {
                        my $cur = item_index( current_item($cmenu) );
                        menu_driver( $cmenu,
                            $t > $cur ? REQ_DOWN_ITEM : REQ_UP_ITEM )
                          for 1 .. abs( $t - $cur );
                        $activate = $YES if $mb & BUTTON1_DOUBLE_CLICKED();
                    }
                }
                next unless $activate;
                $ch = "\r";    # double-click: fall through to the Enter branch
            }
            if ( $ch == KEY_UP ) {
                menu_driver( $cmenu, REQ_UP_ITEM );
            }
            elsif ( $ch == KEY_DOWN ) {
                menu_driver( $cmenu, REQ_DOWN_ITEM );
            }
            elsif ( $ch == KEY_PPAGE ) {
                menu_driver( $cmenu, REQ_SCR_UPAGE );
            }
            elsif ( $ch == KEY_NPAGE ) {
                menu_driver( $cmenu, REQ_SCR_DPAGE );
            }
            elsif ( $ch == KEY_HOME ) {
                menu_driver( $cmenu, REQ_FIRST_ITEM );
            }
            elsif ( $ch == KEY_END ) {
                menu_driver( $cmenu, REQ_LAST_ITEM );
            }
            elsif ( $ch == KEY_RESIZE ) {
                # Terminal resized: tear the windows down and rebuild the menu
                # at the new $LINES/$COLS (ncurses has already updated them).
                # Force a full physical repaint afterwards: rebuilding refreshes
                # only the new window, so without this the area the old (perhaps
                # larger) window occupied keeps stale content until the next key
                # -- the "last resize doesn't refresh" glitch.
                unpost_menu($cmenu);
                del_panel($pan);
                delwin($msub);
                delwin($win);
                $draw_menu->();
                clearok( curscr, 1 );
                refresh(curscr);
            }
            elsif ( $ch == $ctx->{cfg}{keys}{redraw}{code} ) {
                clearok( curscr, 1 );
                refresh(curscr);
            }
            elsif ( $ch == $ctx->{cfg}{keys}{back}{code} or ord($ch) == 27 ) {
                $es = $ES_CANCEL;
                last;
            }
            elsif ( $ch == $ctx->{cfg}{keys}{shell_escape}{code} ) {
                if ( restricted_denies_shell() ) {
                    ;    # disabled in RESTRICTED mode (also off the key bar)
                }
                elsif ( valid_shell($ctx->{cfg}{USER_SHELL}) ) {
                    curs_set($ON) if $ctx->{cfg}{HIDE_CURSOR};
                    call_shell;
                    curs_set($OFF) if $ctx->{cfg}{HIDE_CURSOR};
                    refresh($win);
                }
                else {
                    disp_msg( $win, $BAD_SHELL_MSG, $BAD_SHELL_TITLE );
                }
            }
            elsif ( $ch == $ctx->{cfg}{keys}{exit}{code} ) {
                $es = $ES_EXIT;
                last;
            }
            elsif ( $ch eq "\r" or $ch eq "\n" ) {
                $ci           = item_index( current_item($cmenu) );
                $ctx->{state}{last_item_id} = $menu{items}[$ci]{id};
                if ( $menu{items}[$ci]{action} ) {
                    my $act = CCFE::Action::parse( $menu{items}[$ci]{action} );
                    $action  = $act->{verb};
                    $args    = $act->{args};
                    @actopts = @{ $act->{opts} };

                    my ( $aborted, $opt_es );
                    ( $wait_key, $aborted, $opt_es ) =
                      apply_action_opts( \@actopts, $win,
                        $menu{items}[$ci]{descr} );
                    $es = $opt_es if defined $opt_es;
                    $action = 'ABORTED' if $aborted;

                    if ( $action eq 'menu' ) {
                        ( $es, undef, undef ) =
                          do_menu( $args, $menu{items}[$ci]{descr} );
                        if ( $es and $es < $ES_USER_REQ ) {
                            trace(
"WARNING: $es_str[$es] while reading menu \"$args\""
                            );
                            disp_msg( $win,
                                "$es_str[$es] $LOAD_MENU_ERR_MSG \"$args\"",
                                $MENU_ERR_TITLE );
                        }
                        else {
                            refresh($win);
                        }
                    }
                    elsif ( $action eq 'form' ) {
                        curs_set($ON) if $ctx->{cfg}{HIDE_CURSOR};
                        ( $called_form, $args ) = split /\s+/, $args, 2;
                        $args =~ s/^\s+//;
                        $args =~ s/\s+$//;
                        trace( "call form \"$called_form\", args \"$args\"",
                            $LOG_ACTION_CMD );
                        $es = do_form( $called_form, $menu{items}[$ci]{descr},
                            split /\s+/, $args );
                        curs_set($OFF) if $ctx->{cfg}{HIDE_CURSOR};
                        if ( $es and $es < $ES_USER_REQ ) {
                            trace(
"WARNING: $es_str[$es] while reading form \"$args\""
                            );
                            disp_msg( $win,
                                "$es_str[$es] $LOAD_FORM_ERR_MSG \"$args\"",
                                $FORM_ERR_TITLE );
                        }
                        else {
                            refresh($win);
                        }
                    }
                    elsif ( $action eq 'system' ) {
                        if ( restricted_denies_verb( 'system', $args ) ) {
                            disp_msg( $win, $RESTRICTED_MSG, $RESTRICTED_TITLE );
                        }
                        else {
                            curs_set($ON) if $ctx->{cfg}{HIDE_CURSOR};
                            call_system( $wait_key, $args );
                            curs_set($OFF) if $ctx->{cfg}{HIDE_CURSOR};
                        }
                        refresh($win);
                    }
                    elsif ( $action eq 'exec' ) {
                        if ( restricted_denies_verb( 'exec', $args ) ) {
                            disp_msg( $win, $RESTRICTED_MSG, $RESTRICTED_TITLE );
                        }
                        else {
                            $ctx->{state}{exec_args} = $args;
                        }
                    }
                    elsif ( $action eq 'run' ) {
                        $es = run_browse( $menu{items}[$ci]{descr},
                            $args, $menuname, $menu{path} );
                        refresh($win);
                    }
                    elsif ( $action eq 'ABORTED' ) {
                        trace("user not confirmed action!");
                    }
                    else {
                        trace("unknown action \"$action\"");
                    }
                    last if ( $es // 0 ) == $ES_EXIT;
                }
                else {
                    $exit_id    = $menu{items}[$ci]{id};
                    $exit_descr = $menu{items}[$ci]{descr};
                    trace(
"No action for option \"$exit_id\" of menu \"$menuname\""
                    );
                    if ( $ctx->{cfg}{LAYOUT} != $SIMPLE ) {
                        $exit_descr =~ s/^\s+//;
                        $exit_descr =~ s/\s+$//;
                    }
                    last;
                }
                $LOG_REQUESTED = $NO;
            }
            elsif ( $ch =~ /^\S$/ ) {
                menu_driver( $cmenu, $ch );
            }
            else {
                beep();
            }
        }

        unpost_menu($cmenu);
        free_menu($cmenu);
        foreach $i ( 0 .. $#{ $menu{items} } ) {
            free_item( $menu{items}[$i]{ptr} );
        }
        @fset = ();
        %menu = ();
        undef %menu;

        del_panel($pan);
        delwin($msub);
        delwin($win);
    }
    return ( $es, $exit_id, $exit_descr );
}

sub in {
    my ( $el, @list ) = @_;

    foreach my $scan (@list) {
        return $YES if "$scan" eq "$el";
    }
    return $NO;
}

sub do_list {
    my ( $pwin, $title, $type, $ilist_ref, $selected_ref ) = @_;
    my @il;
    my @fset;
    my @junk;
    my @selected;
    my @items;
    my ( $i, $item, $cmenu, $mpanel, $mwin, $ci, $ciname );
    my ( $rows, $cols, $srch_pattern, $mark );
    my ( $pos_msg, $saveY, $saveX );
    my @top_msg;
    my @lw_keys;
    my $title_y   = ( $ctx->{cfg}{LAYOUT} == $SIMPLE ) ? 1 : 0;
    my $top_msg_y = ( $ctx->{cfg}{LAYOUT} == $SIMPLE ) ? 3 : 2;
    my $nselected = 0;
    my ( $mpad, $px, $mpad_x0, $mpad_y0, $mpad_x1, $mpad_y1 );
    my ( $lflag, $rflag );

    my $es = 0;
  SWITCH: {
        $_ = $type;
        if (/^single\-val$/) {
            @top_msg = @LW_SINGLEVAL_TOP_MSG;
            if ( scalar @$ilist_ref < $MIN_ITEMS_FOR_FIND ) {
                @lw_keys = qw( help redraw back exit );
            }
            else {
                @lw_keys = qw( help redraw back exit find find_next );
            }
            $mark = ' ';
            last SWITCH;
        }
        if (/^multi\-val$/) {
            @top_msg = @LW_MULTIVAL_TOP_MSG;
            if ( scalar @$ilist_ref < $MIN_ITEMS_FOR_FIND ) {
                @lw_keys =
                  qw( help redraw back sel_items exit sel_all unsel_all );
            }
            else {
                @lw_keys =
                  qw( help redraw back sel_items exit find find_next sel_all unsel_all );
            }
            $mark = ( $ctx->{cfg}{LAYOUT} == $SIMPLE ) ? '>' : ' ';
            last SWITCH;
        }
        if (/^display$/) {
            @top_msg = @LW_DISPLAY_TOP_MSG;
            @lw_keys = qw( help redraw back );
            $mark    = ' ';
            my ( $i, $subln1, $subln2 );
            while ( $i <= $#$ilist_ref ) {
                $subln2 = $$ilist_ref[$i];
                while ( length($subln2) > $LW_COLS - 4 ) {
                    $subln1 = substr( $subln2, 0, $LW_COLS - 4 - 1 );
                    $subln2 = substr( $subln2, $LW_COLS - 4 - 1 );
                    $$ilist_ref[$i] = $subln2;
                    splice @$ilist_ref, $i++, 0, $subln1;
                }
                $i++;
            }
            foreach $i ( 0 .. $#$ilist_ref ) {
                $$ilist_ref[$i] = ' ' if !$$ilist_ref[$i];
            }
            last SWITCH;
        }
        if (/^menu$/) {
            last SWITCH;
        }
        else {
            trace("unknown list type \"$type\"");
            return $es, undef;
        }
    }

    # --- issue #1 hotfix ---------------------------------------------------
    # Never build a curses menu from an empty item list.  With no items
    # current_item() returns NULL and the item_index(current_item(...))
    # call further down dies with "argument 0 to Curses function
    # 'item_index' is not a Curses item" -- a hard segfault on some ncurses
    # builds.  Show the standard "list not available" pop-up and bail.
    unless (@$ilist_ref) {
        trace( "do_list: empty item list for type \"$type\"", $LOG_LIST_CMD );
        disp_msg( $pwin, $NULL_LIST_MSG, $NULL_LIST_TITLE );
        return $ES_CANCEL, ();
    }
    # -----------------------------------------------------------------------

    my $y0 = $LW_ROW0;
    my $y1 = $LINES;
    my $x0 = int( ( $COLS - $LW_COLS ) / 2 );
    my $list_height =
      $y1 - $y0 - 2 - $LW_FOOTER_ROWS - $top_msg_y - scalar @top_msg;
    if ( scalar @$ilist_ref < $list_height ) {
        $y0 += $list_height - scalar @$ilist_ref;
        $list_height = scalar @$ilist_ref;
    }
    my $win_height =
      $top_msg_y + ( scalar @top_msg ) + $list_height + $LW_FOOTER_ROWS;
    $win_height += 2;

    my $win_fg_attr  = $ctx->{cfg}{LAYOUT} == $SIMPLE ? A_NORMAL  : A_NORMAL;
    my $win_bg_attr  = $ctx->{cfg}{LAYOUT} == $SIMPLE ? A_NORMAL  : A_REVERSE;
    my $menu_fg_attr = $ctx->{cfg}{LAYOUT} == $SIMPLE ? A_REVERSE : A_NORMAL;
    my $menu_bg_attr = $ctx->{cfg}{LAYOUT} == $SIMPLE ? A_NORMAL  : A_REVERSE;

    $type = lc($type);
    undef(@selected);
    undef(@il);
    undef(@fset);
    undef(@junk);
    undef(@items);
    foreach $i ( 0 .. $#$ilist_ref ) {
        if ( $type ne 'display' ) {
            ( $items[$i]{name}, $items[$i]{descr} ) = split /(?<!\\) /,
              $$ilist_ref[$i], 2;
            $items[$i]{name} =~ s/\\ / /g;
            $items[$i]{name} = ' ' if $items[$i]{name} eq '';
        }
        else {
            $items[$i]{name}  = $$ilist_ref[$i];
            $items[$i]{descr} = '';
        }
        $item = new_item( $items[$i]{name}, $items[$i]{descr} );
        if ( $item eq '' ) {
            fatal(
                "new_item('$items[$i]{name}','$items[$i]{descr}') failed: $item"
            );
        }
        push @il,   $item;
        push @fset, ${$item};
    }
    push @fset, 0;

    # Keep the packed items buffer alive for the menu's lifetime: new_menu()
    # stores the pointer without copying it (see do_menu() for the full
    # explanation).  Freed implicitly when this sub returns, after free_menu().
    my $items_buf = pack 'L!*', @fset;
    $cmenu = new_menu($items_buf);
    if ( $cmenu eq '' ) { fatal("do_list.new_menu() failed") }

    set_menu_mark( $cmenu, $mark );
    set_menu_back( $cmenu, $menu_bg_attr );
    set_menu_fore( $cmenu, $menu_fg_attr );
    if ( $type eq 'multi-val' ) {
        menu_opts_off( $cmenu, O_ONEVALUE );
    }
    else {
        menu_opts_on( $cmenu, O_ONEVALUE );
    }
    set_menu_format( $cmenu, $list_height, 1 );

    $mwin = newwin( $win_height, $LW_COLS, $y0, $x0 );
    bkgd( $mwin, $menu_bg_attr );
    box( $mwin, 0, 0 );
    if ( defined($title) ) {
        $title = " $title " if $ctx->{cfg}{LAYOUT} == $NORMAL;
    }
    addstr( $mwin, $title_y, int( ( $LW_COLS - disp_width($title) ) / 2 ),
        $title );
    init_top( $mwin, $YES, $top_msg_y, scalar @top_msg, @top_msg );
    init_footer( $mwin, $YES, $LW_FOOTER_ROWS, @lw_keys );
    scale_menu( $cmenu, $rows, $cols );

    $mpanel = new_panel($mwin);
    if ( $ctx->{cfg}{LAYOUT} == $NORMAL ) {
        $mlmargin = int( ( $LW_COLS - $cols ) / 2 );
        $mlmargin = 1 if $mlmargin < 1;
    }
    else {
        $mlmargin = 2;
    }

    $mpad_x0 = $x0 + $mlmargin;
    $mpad_y0 = $y0 + ( scalar @top_msg ) + $top_msg_y + 1;
    $mpad_x1 = $x0 + $LW_COLS - 2;
    $mpad_y1 = $mpad_y0 + $list_height;

    $mpad = newpad( $list_height, $LW_PAD_COLS );
    bkgd( $mpad, $menu_bg_attr );
    doupdate();

    set_menu_win( $cmenu, $mwin );
    set_menu_sub( $cmenu, $mpad );
    keypad( $mwin, $ON );

    post_menu($cmenu);
    if ( $type eq 'multi-val' ) {
        foreach $i ( 0 .. $#il ) {
            foreach $scan (@$selected_ref) {
                if ( $scan eq $items[$i]{name} ) {
                    set_item_value( $il[$i], $YES );
                    $nselected++;
                }
            }
        }
    }
    refresh($mwin);
    $px = 0;
    while (1) {
        prefresh( $mpad, 0, $px, $mpad_y0, $mpad_x0, $mpad_y1, $mpad_x1 );
        $rflag = $lflag = ' ';
        $rflag = '>' if $mlmargin + $cols - $LW_COLS - $px >= 0;
        $lflag = '<' if $px > 0;
        # issue #1: guard against a NULL current item -- item_index(undef)
        # segfaults.  The empty-list check at the top of do_list should make
        # this unreachable, but keep the call site defensive.
        my $cur_item = current_item($cmenu);
        my $cur_idx  = $cur_item ? item_index($cur_item) : -1;
        $pos_msg = sprintf( "  %s%d/%d%s%s",
            $lflag, $cur_idx + 1,
            item_count($cmenu),
            ( $type eq 'multi-val' ) ? ":$nselected" : '', $rflag );
        getyx( $mwin, $saveY, $saveX );
        addstr( $mwin, $title_y + 1, $LW_COLS - length($pos_msg) - 1,
            $pos_msg );
        move( $mwin, $saveY, $saveX );
        my $ch = getch($mwin);

        if ( $ch == KEY_UP ) {
            menu_driver( $cmenu, REQ_UP_ITEM );
        }
        elsif ( $ch == KEY_DOWN ) {
            menu_driver( $cmenu, REQ_DOWN_ITEM );
        }
        elsif ( $ch == KEY_LEFT ) {
            $px-- if $px > 0;
        }
        elsif ( $ch == KEY_RIGHT ) {
            $px++ if $mlmargin + $cols - $LW_COLS - $px >= 0;
        }
        elsif ( $ch == KEY_HOME ) {
            menu_driver( $cmenu, REQ_FIRST_ITEM );
        }
        elsif ( $ch == KEY_END ) {
            menu_driver( $cmenu, REQ_LAST_ITEM );
        }
        elsif ( $ch == KEY_PPAGE ) {
            menu_driver( $cmenu, REQ_SCR_UPAGE );
        }
        elsif ( $ch == KEY_NPAGE ) {
            menu_driver( $cmenu, REQ_SCR_DPAGE );
        }
        elsif ( $ch eq '/' and in( 'find', @lw_keys ) ) {
            ( $es, $srch_pattern ) =
              ask_string( $SEARCH_PTRN_TITLE, $SEARCH_PTRN_PROMPT );
            if ( ( $es // 0 ) == $ES_EXIT ) {
                $ch = $ctx->{cfg}{keys}{exit}{code};
                last;
            }
            noutrefresh($pwin);
            noutrefresh($mwin);
            doupdate;
            set_menu_pattern( $cmenu, $srch_pattern );
        }
        elsif ( $ch eq 'n' and in( 'find_next', @lw_keys ) ) {
            menu_driver( $cmenu, REQ_NEXT_MATCH );
        }
        elsif ( $ch == KEY_RESIZE ) {
            # Re-centre the pop-up for the new terminal size and repaint.  The
            # list keeps its own size; a full content reflow (and reflowing the
            # form/menu underneath, which does not see this event) is a further
            # refinement.
            $y0 = $LW_ROW0;
            $y0 += $list_height - scalar @$ilist_ref
              if scalar @$ilist_ref < $list_height;
            $x0 = int( ( $COLS - $LW_COLS ) / 2 );
            $x0 = 0 if $x0 < 0;
            mvwin( $mwin, $y0, $x0 );
            $mpad_x0 = $x0 + $mlmargin;
            $mpad_y0 = $y0 + ( scalar @top_msg ) + $top_msg_y + 1;
            $mpad_x1 = $x0 + $LW_COLS - 2;
            $mpad_y1 = $mpad_y0 + $list_height;
            clearok( curscr, 1 );
            refresh(curscr);
        }
        elsif ( $ch == $ctx->{cfg}{keys}{redraw}{code} ) {
            clearok( curscr, 1 );
            refresh(curscr);
        }
        elsif ( ( $ch == $ctx->{cfg}{keys}{back}{code} or ord($ch) == 27 )
            and in( 'back', @lw_keys ) )
        {
            $es = $ES_CANCEL;
            last;
        }
        elsif ( $ch == $ctx->{cfg}{keys}{exit}{code} and in( 'exit', @lw_keys ) ) {
            $es = $ES_EXIT;
            last;
        }
        elsif ( ( $ch == $ctx->{cfg}{keys}{sel_items}{code} or $ch eq ' ' )
            and $type eq 'multi-val' )
        {

            $ci = current_item($cmenu);
            set_item_value( $ci, !item_value($ci) );
            $nselected += item_value($ci) ? 1 : -1;
            menu_driver( $cmenu, REQ_DOWN_ITEM );
        }
        elsif ( uc($ch) eq 'A' and in( 'sel_all', @lw_keys ) ) {
            foreach $i ( 0 .. $#il ) {
                set_item_value( $il[$i], $YES );
            }
            $nselected = $#il + 1;
        }
        elsif ( uc($ch) eq 'U' and in( 'unsel_all', @lw_keys ) ) {
            foreach $i ( 0 .. $#il ) {
                set_item_value( $il[$i], $NO );
            }
            $nselected = 0;
        }
        elsif ( $ch eq "\r" or $ch eq "\n" ) {
            @selected = ();
            if ( $type eq 'single-val' ) {
                $ci     = current_item($cmenu);
                $ciname = item_name($ci);
                push @selected, $ciname if $type eq 'single-val';
            }
            else {
                foreach $i ( 0 .. $#il ) {
                    if ( item_value( $il[$i] ) ) {
                        $ciname = item_name( $il[$i] );
                        $ciname =~ s/^\s+//;
                        $ciname =~ s/\s+$//;
                        push @selected, $ciname;
                    }
                }
            }
            last;
        }
        else {
            beep();
        }
    }

    del_panel($mpanel);
    unpost_menu($cmenu);
    delwin($mpad);
    delwin($mwin);
    free_menu($cmenu);
    map { free_item($_) } @il;
    refresh($pwin);
    @selected = () if ( $ch == $ctx->{cfg}{keys}{back}{code} or ord($ch) == 27 );
    return $es, @selected;
}

# After a page change (REQ_NEXT_PAGE/REQ_PREV_PAGE) libform updates the
# logical page but does not repaint a derwin sub-window on its own; un-posting
# and re-posting the form draws the now-current page's fields (the field
# buffers, i.e. anything the user typed, are preserved).  ncurses' update
# optimisation also does not reliably notice the sub-window changing under the
# switch, so clearok() forces a full repaint on the next refresh.
sub redraw_form_page {
    my ( $cform, $win ) = @_;
    unpost_form($cform);
    post_form($cform);
    clearok( $win, 1 );
    return;
}

# Run a form's `init { command:... }` before it is drawn (TD-3: lifted out of
# do_form).  The command's `id=value` stdout pre-fills the field-value map; the
# special CCFE_{REMOVE,ENABLE,DISABLE}_FIELDS ids accumulate into the caller's
# lists; stderr is shown in a pop-up.  Returns true when the command failed
# (non-zero exit) so do_form should abort; the caller owns the window teardown.
sub run_form_init {
    my ( $form, $formname, $win, $field_vals, $remove, $enable, $disable ) = @_;
    return 0 unless $form->{init};

    my ( $action, $args ) = split /:/, $form->{init}, 2;
    unless ( $action eq 'command' ) {
        trace("unknown form init type \"$action\"");
        return 0;
    }

    curs_set($OFF) if $ctx->{cfg}{HIDE_CURSOR};
    my ( $wpan, $wwin ) = open_wait_msg;
    %{$field_vals} = ();

    my @res = ();
    my @err = ();
    trace( "init form: executing \"$args\"", $LOG_INITFORM_OUT );
    exec_command( $args, $form->{path}, \@res, \@err );
    trace( "init form exit status: $ctx->{state}{child_es}", $LOG_INITFORM_OUT );
    trace( "init form stdout:", $LOG_INITFORM_OUT );
    trace( "  \"$_\"",          $LOG_INITFORM_OUT ) for @res;
    if (@err) {
        do_list( $win, $INIT_FORM_ERR_MSG, 'display', \@err, undef );
        trace( "init form stderr:", $LOG_INITFORM_OUT );
        trace( "  $_",              $LOG_INITFORM_OUT ) for @err;
    }

    trace( "init field value(s) \"$formname\":", $LOG_FIELDS_VAL );
    foreach my $s (@res) {
        my ( $id, $val ) = split /\s*=\s*/, $s, 2;
        if (
            in( $id,
                ( $INIT_REMOVE_FIELDS, $INIT_ENABLE_FIELDS, $INIT_DISABLE_FIELDS )
            )
          )
        {
            my @fl = split /\s*,\s*/, $val;
            if ( $id =~ /^$INIT_REMOVE_FIELDS$/ ) {
                push( @{$remove}, @fl );
            }
            elsif ( $id =~ /^$INIT_ENABLE_FIELDS$/ ) {
                push( @{$enable}, @fl );
            }
            elsif ( $id =~ /^$INIT_DISABLE_FIELDS$/ ) {
                push( @{$disable}, @fl );
            }
            trace( "$id is \"" . join( ',', @fl ) . "\"" );
        }
        else {
            $field_vals->{$id} = $val;
            trace( "  $s=\"$val\"", $LOG_FIELDS_VAL );
        }
    }

    close_wait_msg( $wpan, $wwin, $win );
    curs_set($ON) if $ctx->{cfg}{HIDE_CURSOR};
    return $ctx->{state}{child_es} ? 1 : 0;
}

# Build the curses fields for a forms logical fields (TD-3: lifted out of
# do_form -- its single largest block).  Per field it creates the 7 curses
# fields (label, the two flag markers, the two value delimiters, the dot leader
# and the value), pushing them onto \@{$fp}/\@{$fset} and recording geometry
# back onto the field; removed fields (CCFE_REMOVE_FIELDS) are spliced out.
# Returns ($npages, $all_ids) -- the page count and the "%{ID}..." all-fields
# substitution string.
sub build_form_fields {
    my ( $form, $field_vals, $fp, $fset, $remove, $enable, $disable,
        $mwinr, $lflags_size, $rflags_size ) = @_;
    my ( $i, $y, $npages, $all_ids ) = ( 0, 0, 0, "" );
    my ( $id, $label, $len, $hscroll, $hidden, $type, $default, $script,
        $fpad, $val, $field, $dots, $c );

    while ( $i <= $#{ $form->{fields} } ) {
        $id = $form->{fields}[$i]{id};
        unless ( in( $id, @{$remove} ) ) {
            if ( in( $id, @{$enable} ) ) {
                $form->{fields}[$i]{enabled} = $YES;
                trace("$INIT_ENABLE_FIELDS enabled field ID \"$id\"")
                  ;    #$LOG_FIELDS_VAL
            }
            if ( in( $id, @{$disable} ) ) {
                $form->{fields}[$i]{enabled} = $NO;
                trace("$INIT_DISABLE_FIELDS disabled field ID \"$id\"")
                  ;    #$LOG_FIELDS_VAL
            }
            $label   = $form->{fields}[$i]{label};
            $len     = $form->{fields}[$i]{len};
            $hscroll = $form->{fields}[$i]{hscroll};
            $hidden  = $form->{fields}[$i]{hidden};
            $type    = $form->{fields}[$i]{type};
            $default = $form->{fields}[$i]{default};
            $script  = $form->{fields}[$i]{help_script};
            $fpad    = $hidden ? $ctx->{cfg}{HFIELD_PAD} : $ctx->{cfg}{FIELD_PAD};

            $all_ids .= " " if !( $form->{fields}[$i]{option} );
            $all_ids .= "%{$id}" if $id !~ /^$FSEP_ID_PRFX/;
            if ( $type == $SEPARATOR and !defined($label) ) {
                $label =
                  $field_vals->{$id} ? $field_vals->{$id} : 'ERROR!';
            }
            if ( $ctx->{cfg}{LAYOUT} == $SIMPLE ) {
                $len = $COLS - ( 52 + $rflags_size + 2 )
                  if ( 52 + $len + $rflags_size + 2 > $COLS );
            }
            my $lflags_x = 0;
            my $label_x =
              $lflags_x +
              $lflags_size +
              $form->{fields}[$i]{htab} * $HTAB_COLS;
            my $lw = disp_width($label);    # label width in columns
            $val = '';
            $val = $default if defined($default);
            $val = $field_vals->{$id} if defined( $field_vals->{$id} );
            $val = substr( $val, 0, $len )
              if ( $hscroll == $NO )
              and ( length($val) > $len );

            # Value/flag columns and wrapping.  The value is right-aligned to
            # the screen edge (classic SMIT look), so it expands to use the
            # width on a wide terminal.  When the label is too long to leave
            # at least $FIELD_VALUE_GAP columns before that value -- a long
            # label on a narrow terminal -- the label wraps onto its own
            # full-width line(s) and the value drops to the row after the
            # last label line, so it is never pushed off-screen or truncated.
            # The geometry is pure (CCFE::Layout); resize_form reuses it.
            my $auto = ( $ctx->{cfg}{LAYOUT} == $NORMAL and $ctx->{cfg}{FIELD_VALUE_POS} == -1 );
            my $geom = CCFE::Layout::field_geometry(
                {
                    cols        => $COLS,
                    len         => $len,
                    label_x     => $label_x,
                    label_w     => $lw,
                    rflags_size => $rflags_size,
                    value_pos   => $ctx->{cfg}{FIELD_VALUE_POS},
                    gap         => $FIELD_VALUE_GAP,
                    auto        => $auto,
                }
            );
            my $val_x     = $geom->{val_x};
            my $label_w   = $geom->{label_w};
            my $wrap_rows = $geom->{wrap_rows};
            my $dots_x    = $geom->{dots_x};
            my $lvald_x   = $geom->{lvald_x};
            my $rvald_x   = $geom->{rvald_x};
            my $rflags_x  = $geom->{rflags_x};
            trace(
                "do_form: wrapped label \"$id\" over $wrap_rows line(s)",
                $LOG_NORMAL
            ) if $wrap_rows;
            $form->{fields}[$i]{wrap_rows} = $wrap_rows;

            # Advance to this field's top row, breaking to a new page if the
            # whole (possibly multi-row) block would not fit on this one.
            my $pg = CCFE::Layout::page_advance(
                {
                    y         => $y,
                    vtab      => $form->{fields}[$i]{vtab},
                    wrap_rows => $wrap_rows,
                    mwinr     => $mwinr,
                }
            );
            $y = $pg->{y};
            my $vr = $pg->{vr};    # row of the value and its markers

            $field =
              $wrap_rows
              ? new_field( $wrap_rows, $label_w, $y, $label_x, 0, 0 )
              : new_field( 1, $lw, $y, $label_x, 0, 0 );
            if ( $field eq '' ) { fatal("new_field(LABEL $label) failed") }
            set_field_buffer( $field, 0, $label );
            field_opts_off( $field, O_ACTIVE );
            field_opts_off( $field, O_EDIT );
            set_field_fore( $field, $ctx->{cfg}{labelFg} );
            set_field_back( $field, $ctx->{cfg}{labelBg} );

            if ( !$y ) {
                set_new_page( $field, 1 );
                $npages++;
            }
            push @{$fp},   $field;
            push @{$fset}, ${$field};

            $field = new_field( 1, $lflags_size, $vr, $lflags_x, 0, 0 );
            if ( $field eq '' ) {
                fatal("new_field(PRE_FLAGS $label) failed");
            }
            set_field_buffer( $field, 0,
                sprintf( "%s ", $form->{fields}[$i]{required} ? '*' : ' ' ) );
            field_opts_off( $field, O_ACTIVE );
            set_field_fore( $field, $ctx->{cfg}{labelFg} );    # blend with the panel
            set_field_back( $field, $ctx->{cfg}{labelBg} );
            if ( !$ctx->{cfg}{SHOW_FIELD_FLAGS} ) {
                field_opts_off( $field, O_VISIBLE );
            }
            field_opts_off( $field, O_VISIBLE ) if ( $type == $SEPARATOR );
            push @{$fp},   $field;
            push @{$fset}, ${$field};

            $field = new_field( 1, $rflags_size, $vr, $rflags_x, 0, 0 );
            if ( $field eq '' ) {
                fatal("new_field(POST_FLAGS $label) failed");
            }
            set_field_buffer(
                $field, 0,
                sprintf( "%s%s",
                    $form->{fields}[$i]{list_cmd}             ? '+' : ' ',
                    ( $form->{fields}[$i]{type} == $NUMERIC ) ? '#' : ' ' )
            );
            field_opts_off( $field, O_ACTIVE );
            set_field_fore( $field, $ctx->{cfg}{labelFg} );    # blend with the panel
            set_field_back( $field, $ctx->{cfg}{labelBg} );
            if ( !$ctx->{cfg}{SHOW_FIELD_FLAGS} ) {
                field_opts_off( $field, O_VISIBLE );
            }
            field_opts_off( $field, O_VISIBLE ) if ( $type == $SEPARATOR );
            push @{$fp},   $field;
            push @{$fset}, ${$field};

            $field = new_field( 1, 1, $vr, $lvald_x, 0, 0 );
            if ( $field eq '' ) {
                fatal("new_field(BEGIN_DELIMITER $label) failed");
            }
            if ( $form->{fields}[$i]{enabled} ) {
                set_field_buffer( $field, 0, $ctx->{cfg}{fval_delim}[0] );
            }
            else {
                set_field_buffer( $field, 0, ' ' );
            }
            field_opts_off( $field, O_ACTIVE );
            field_opts_off( $field, O_EDIT );
            set_field_fore( $field, $ctx->{cfg}{labelFg} );
            set_field_back( $field, $ctx->{cfg}{labelBg} );
            field_opts_off( $field, O_VISIBLE ) if ( $type == $SEPARATOR );
            push @{$fp},   $field;
            push @{$fset}, ${$field};
            $field = new_field( 1, 1, $vr, $rvald_x, 0, 0 );

            if ( $field eq '' ) {
                fatal("new_field(END_DELIMITER $label) failed");
            }
            if ( $form->{fields}[$i]{enabled} ) {
                if ( length($val) > $len ) {
                    set_field_buffer( $field, 0, '>' );
                }
                else {
                    set_field_buffer( $field, 0, $ctx->{cfg}{fval_delim}[1] );
                }
            }
            else {
                set_field_buffer( $field, 0, ' ' );
            }
            field_opts_off( $field, O_ACTIVE );
            field_opts_off( $field, O_EDIT );
            set_field_fore( $field, $ctx->{cfg}{labelFg} );
            set_field_back( $field, $ctx->{cfg}{labelBg} );
            field_opts_off( $field, O_VISIBLE ) if ( $type == $SEPARATOR );
            push @{$fp},   $field;
            push @{$fset}, ${$field};

            if ($ctx->{cfg}{SHOW_DOTS}) {
                $dots = '';
                for ( $c = $dots_x - 1 ; $c < $lvald_x - 2 ; $c++ ) {
                    $dots .= ( $c % 2 ) ? '.' : ' ';
                }
                $dots .= ': ';
            }
            else {
                $dots = ' ';
            }
            $field = new_field( 1, length($dots), $vr, $dots_x, 0, 0 );
            if ( $field eq '' ) { fatal("new_field(DOTS $label) failed") }
            set_field_buffer( $field, 0, $dots );
            field_opts_off( $field, O_ACTIVE );
            field_opts_off( $field, O_EDIT );
            set_field_fore( $field, $ctx->{cfg}{labelFg} );    # dots adopt the panel/label colour
            set_field_back( $field, $ctx->{cfg}{labelBg} );
            field_opts_off( $field, O_VISIBLE ) if ( $type == $SEPARATOR );
            push @{$fp},   $field;
            push @{$fset}, ${$field};

            $field = new_field( 1, $len, $vr, $val_x, 0, 1 );
            if ( $field eq '' ) { fatal("new_field(VAL $label) failed") }
            field_opts_off( $field, O_AUTOSKIP );
            unless ( $form->{fields}[$i]{enabled} ) {
                field_opts_off( $field, O_ACTIVE );
            }
            elsif ( !( $type & $BOOLEAN ) ) {
                set_field_pad( $field, $fpad );
            }
            if ($hscroll) {
                field_opts_off( $field, O_STATIC );
            }
            else {
                field_opts_on( $field, O_STATIC );
            }
            if ($hidden) {
                field_opts_off( $field, O_PUBLIC );
            }
            else {
                field_opts_on( $field, O_PUBLIC );
            }
            set_field_buffer( $field, 0, $val );
            set_field_buffer( $field, 1, $val );
            $form->{fields}[$i]{value} = $val;
            if ( $ctx->{cfg}{LAYOUT} == $NORMAL and $type == $NUMERIC ) {
                set_field_just( $field, JUSTIFY_RIGHT );
            }

            if ( $form->{fields}[$i]{enabled} ) {
                set_field_fore( $field, $form->{fields}[$i]{valueFg} );
                set_field_back( $field, $form->{fields}[$i]{valueBg} );
            }
            else {
                set_field_fore( $field, $ctx->{cfg}{labelFg} );
                set_field_back( $field, $ctx->{cfg}{labelBg} );
            }
            $y = $vr + 1;    # next field starts below the value row
            field_opts_off( $field, O_VISIBLE ) if ( $type == $SEPARATOR );
            push @{$fp}, $field;
            $form->{fields}[$i]{ptr} = $field;
            push @{$fset}, ${$field};
            $i++;
        }
        else {
            splice @{ $form->{fields} }, $i, 1;
            trace("$INIT_REMOVE_FIELDS removed field ID \"$id\"")
              ;    #$LOG_FIELDS_VAL
        }
    }
    push @{$fset}, 0;
    return ( $npages, $all_ids );
}

# Reflow and rebuild a form for a new terminal size (TD-3: lifted out of
# do_form).  Re-lays-out every field for the current $LINES/$COLS (re-right-
# aligning and re-wrapping values, recreating the width-dependent label/dot
# fields and moving the fixed ones), rebuilds the window/sub-window/panel and
# the form around the preserved field set, and re-posts it.  @{$fp} is mutated
# in place (recreated fields); the rebuilt handles are returned.
sub resize_form {
    my ( $form, $fp, $win, $fsub, $pan, $cform, $fields_buf,
        $rflags_size, $title, $formname, $ovl_mode ) = @_;
    my ( $npages, $mwinr );
    my @fset;
    my $eff_lines = $LINES < 24 ? 24 : $LINES;
    my $eff_cols  = $COLS < 80  ? 80 : $COLS;
    $mwinr =
      $eff_lines -
      ( $FS_HEADER_ROWS + $FS_TOP_ROWS + $FS_BOTTOM_ROWS
          + $ctx->{cfg}{FS_FOOTER_ROWS} );

    # Commit the field currently being edited to its buffer so the
    # value survives the free_form/new_form cycle below.
    form_driver( $cform, REQ_VALIDATION );
    unpost_form($cform);
    free_form($cform);

    # Re-lay-out every field for the new width and height.  Value fields
    # re-right-align to the current $COLS and re-wrap (the value column
    # and the wrap both depend on the width, so this is a horizontal
    # *and* vertical reflow, not just a move): the value's column and the
    # dot run change, and the label's height/width change when it wraps,
    # so the two width-dependent fields (label, dots) are recreated and
    # the five fixed-content fields (the flag/delimiter markers and the
    # value -- whose buffer holds the user's input) are moved, preserving
    # their contents.  Separators and explicitly-placed fields keep their
    # columns.  Each logical field's block (wrap_rows label lines + the
    # value row) is kept whole on one page.  While here, measure the
    # widest field so the rebuilt window holds them all (ncurses allows
    # an over-sized window on a smaller screen, so post_form() never
    # fails with E_NO_ROOM and crashes the loop).
    my $yy        = 0;
    my $max_right = 0;
    $npages = 0;
    foreach my $li ( 0 .. $#{ $form->{fields} } ) {
        my $f      = $form->{fields}[$li];
        my $is_sep = ( $f->{type} == $SEPARATOR );
        my $reflow =
          ( $ctx->{cfg}{LAYOUT} == $NORMAL and $ctx->{cfg}{FIELD_VALUE_POS} == -1 and !$is_sep );
        my $label   = $f->{label};
        my $len     = $f->{len};
        my $label_x = $FIELD_LMARGIN + ( $f->{htab} || 0 ) * $HTAB_COLS;
        my $wr      = $f->{wrap_rows} || 0;

        my $lw = disp_width($label);    # label width in columns
        my ( $val_x, $dots_x, $lvald_x, $rvald_x, $rflags_x, $label_w );
        if ($reflow) {
            # Same pure geometry do_form first laid the field out with.
            my $geom = CCFE::Layout::field_geometry(
                {
                    cols        => $COLS,
                    len         => $len,
                    label_x     => $label_x,
                    label_w     => $lw,
                    rflags_size => $rflags_size,
                    value_pos   => $ctx->{cfg}{FIELD_VALUE_POS},
                    gap         => $FIELD_VALUE_GAP,
                    auto        => 1,
                }
            );
            $val_x          = $geom->{val_x};
            $label_w        = $geom->{label_w};
            $wr             = $geom->{wrap_rows};
            $dots_x         = $geom->{dots_x};
            $lvald_x        = $geom->{lvald_x};
            $rvald_x        = $geom->{rvald_x};
            $rflags_x       = $geom->{rflags_x};
            $f->{wrap_rows} = $wr;
        }

        my $pg = CCFE::Layout::page_advance(
            {
                y         => $yy,
                vtab      => $f->{vtab} || 0,
                wrap_rows => $wr,
                mwinr     => $mwinr,
            }
        );
        $yy = $pg->{y};
        my $page_start = $pg->{page_start} ? 1 : 0;
        $npages++ if $page_start;
        my $vr = $pg->{vr};

        if ($reflow) {
            # Recreate the label (its height/width follow the wrap) ...
            free_field( $fp->[ $li * 7 ] );
            my $lab =
                $wr
              ? new_field( $wr, $label_w, $yy, $label_x, 0, 0 )
              : new_field( 1, $lw, $yy, $label_x, 0, 0 );
            set_field_buffer( $lab, 0, $label );
            field_opts_off( $lab, O_ACTIVE );
            field_opts_off( $lab, O_EDIT );
            set_field_fore( $lab, $ctx->{cfg}{labelFg} );
            set_field_back( $lab, $ctx->{cfg}{labelBg} );
            $fp->[ $li * 7 ] = $lab;

            # ... and the dot run (its width follows the value column).
            my $dots;
            if ($ctx->{cfg}{SHOW_DOTS}) {
                $dots = '';
                for ( my $c = $dots_x - 1 ; $c < $lvald_x - 2 ; $c++ ) {
                    $dots .= ( $c % 2 ) ? '.' : ' ';
                }
                $dots .= ': ';
            }
            else { $dots = ' ' }
            free_field( $fp->[ $li * 7 + 5 ] );
            my $dot = new_field( 1, length($dots), $vr, $dots_x, 0, 0 );
            set_field_buffer( $dot, 0, $dots );
            field_opts_off( $dot, O_ACTIVE );
            field_opts_off( $dot, O_EDIT );
            set_field_fore( $dot, $ctx->{cfg}{labelFg} );    # dots adopt the panel
            set_field_back( $dot, $ctx->{cfg}{labelBg} );
            $fp->[ $li * 7 + 5 ] = $dot;

            # Move the markers and the value field to the new columns.
            move_field( $fp->[ $li * 7 + 1 ], $vr, 0 );
            move_field( $fp->[ $li * 7 + 2 ], $vr, $rflags_x );
            move_field( $fp->[ $li * 7 + 3 ], $vr, $lvald_x );
            move_field( $fp->[ $li * 7 + 4 ], $vr, $rvald_x );
            move_field( $fp->[ $li * 7 + 6 ], $vr, $val_x );
        }
        else {
            # Separator / explicit placement: keep columns, move rows.
            foreach my $k ( 0 .. 6 ) {
                my ( $fr, $fc, $frw, $fcl, $fnr, $fnb );
                field_info( $fp->[ $li * 7 + $k ], $fr, $fc, $frw, $fcl,
                    $fnr, $fnb );
                move_field( $fp->[ $li * 7 + $k ],
                    ( $k == 0 ? $yy : $vr ), $fcl );
            }
        }

        foreach my $k ( 0 .. 6 ) {
            my ( $fr, $fc, $frw, $fcl, $fnr, $fnb );
            field_info( $fp->[ $li * 7 + $k ], $fr, $fc, $frw, $fcl, $fnr,
                $fnb );
            $max_right = $fcl + $fc if $fcl + $fc > $max_right;
        }
        set_new_page( $fp->[ $li * 7 ], $page_start );
        $yy = $vr + 1;
    }

    # The label and dot fields were recreated, so rebuild the packed
    # field set the new form is constructed from.
    @fset = map { ${$_} } @{$fp};
    push @fset, 0;
    $fields_buf = pack 'L!*', @fset;
    $eff_cols = $max_right if $eff_cols < $max_right;
    trace(
"resize_form: LINES=$LINES COLS=$COLS eff=${eff_lines}x${eff_cols} mwinr=$mwinr max_right=$max_right",
        $LOG_NORMAL
    );

    del_panel($pan) if $pan;
    delwin($fsub)   if $fsub;
    delwin($win)    if $win;
    $win = newwin( $eff_lines, $eff_cols, 0, 0 );

    # Guard the rebuilt curses objects: if any comes back NULL (an
    # empty string from the XS binding) continuing would call form
    # routines on an invalid handle and crash -- or, worse, leak a
    # libform error code out as the process exit status.  Restore the
    # terminal and abort cleanly with a diagnostic instead.
    if ( !$win ) {
        fatal("resize_form: newwin(${eff_lines}x${eff_cols}) failed");
    }
    $pan  = new_panel($win);
    $fsub = derwin( $win, $mwinr, $eff_cols,
        $FS_HEADER_ROWS + $FS_TOP_ROWS, 0 );
    if ( !$fsub ) {
        fatal("resize_form: derwin(${mwinr}x${eff_cols}) failed");
    }
    bkgd( $win,  $ctx->{cfg}{MENU_SCREEN_ATTR} );
    bkgd( $fsub, $ctx->{cfg}{MENU_SCREEN_ATTR} );
    $cform = new_form($fields_buf);
    if ( !$cform ) {
        fatal('resize_form: new_form() failed');
    }
    set_form_win( $cform, $win );
    set_form_sub( $cform, $fsub );
    form_opts_off( $cform, O_BS_OVERLOAD );
    keypad( $win, $ON );
    init_title( $win, $FS_HEADER_ROWS, $title );
    disp_page( $win, form_page($cform) + 1, $npages, 'form',
        $formname );
    init_top( $win, $NO, $FS_HEADER_ROWS, $FS_TOP_ROWS,
        @{ $form->{top} } );
    init_footer( $win, $NO, $ctx->{cfg}{FS_FOOTER_ROWS}, @FSKeys );
    my $pr = post_form($cform);
    trace( "resize_form: post_form => $pr ($npages page(s))",
        $LOG_NORMAL );
    form_driver( $cform, $ovl_mode ? REQ_OVL_MODE : REQ_INS_MODE );
    form_driver( $cform, REQ_END_LINE );
    clearok( $win, 1 );
    refresh($win);
    return ( $win, $fsub, $pan, $cform, $fields_buf, $npages, $mwinr );
}

# do_form's Enter/submit handler, extracted from the event loop (TD-3).  Syncs
# the visible field buffers into the field values, refuses an empty required
# field, then parses and dispatches the form's action (run/form/system/exec)
# exactly as the inline arm did.  $es is threaded in and returned (run_browse /
# a nested do_form / a confirm-abort can change it); exec selection is recorded
# on the shared $ctx as before.  The three per-form closures are passed in
# because they capture this call's %form/$cform/@fp.
# do_form's value-list (F2) handler, extracted from the event loop (TD-3).
# Resolves the current field's list_cmd (a `command:` run with %{ID} field
# substitution, or a `const:` literal list), pops the chooser, and writes the
# selection back into the field.  Returns ($es, $break): $break is true when
# the chooser asked to quit the whole UI (ES_EXIT), so the caller exits the
# event loop exactly as the inline `last` did.  $check_val_changes is passed in
# (it captures this call's %form/$cform/@fp).
# do_form's TAB / Shift-TAB handler, extracted from the event loop (TD-3).  For
# a field with a `const:single-val` list_cmd it cycles the field through the
# list's values in place (forward on TAB, backward on Shift-TAB), wrapping
# round; any other list_cmd kind beeps.  Mutates the field buffer directly;
# $check_val_changes (which captures this call's %form/$cform/@fp) is passed in.
# do_form's Save handler, extracted from the event loop (TD-3).  Syncs the
# visible field buffers into the field values and writes a labelled, aligned
# dump of every non-separator field to the log, then confirms (or reports a log
# write error).  $sync_fields_val (capturing this call's %form/$cform) is passed
# in.  The label-padding eval-string is the legacy idiom kept verbatim.
sub form_save_fields {
    my ( $form, $win, $title, $formname, $sync_fields_val ) = @_;

    $sync_fields_val->();
    $LOG_REQUESTED = $YES;
    trace( "\n\n" . '-' x 80, $LOG_NORMAL );
    my ( $ss, $mm, $hh, $dd, $mt, $yy ) = localtime(time);
    trace(
        "DATE  : "
          . sprintf( "%02d/%02d/%d, %02d:%02d:%02d\n",
            $dd, ++$mt, 1900 + $yy, $hh, $mm, $ss )
          . "SCREEN: $title  [$formname]\n"
          . "DESCR : Save fields value",
        $LOG_NORMAL
    );
    trace( '-' x 80, $LOG_NORMAL );
    my $maxlen = 0;
    foreach my $i ( 0 .. $#{ $form->{fields} } ) {
        my $len = length( $form->{fields}[$i]{label} )
          if $form->{fields}[$i]{type} != $SEPARATOR;
        $maxlen = $len if $len > $maxlen;
    }
    foreach my $i ( 0 .. $#{ $form->{fields} } ) {
        if ( $form->{fields}[$i]{type} != $SEPARATOR ) {
            my $buff = eval
              "sprintf \"%-${maxlen}s\",\$form->{fields}[\$i]{label}";
            trace(
                sprintf( "%s:'%s'",
                    $buff, $form->{fields}[$i]{value} ),
                $LOG_NORMAL
            );
        }
    }
    $LOG_REQUESTED = $NO;
    if ($@) {
        chop($@);
        disp_msg( $win, "$@ $LOG_WRITE_ERROR_MSG",
            $LOG_WRITE_ERROR_TITLE );
    }
    else {
        disp_msg( $win, $SAVE_FIELDVAL_MSG, $SAVE_FIELDVAL_TITLE );
    }
    return;
}

sub form_tab_cycle {
    my ( $form, $cform, $ch, $check_val_changes ) = @_;

    my ( $name, $newidx );
    my $fi     = int( field_index( current_field($cform) ) / 7 );
    my @vals   = ();
    my @list   = ();
    my $actval = field_buffer( current_field($cform), 0 );
    $actval =~ s/\s+$//;
    $actval =~ s/^\s+//;
    my ( $action, $type, $args ) = split /:/,
      $form->{fields}[$fi]{list_cmd}, 3;

    if ( lc($action) eq 'const' and lc($type) eq 'single-val' ) {
        $args =~ s/^ *"//;
        $args =~ s/" *$//;
        @list = split /" *, *"/, $args;
        foreach my $s (@list) {
            ( $name, undef ) = split /(?<!\\) /, $s, 2;
            $name =~ s/\\ / /g;
            $name = ' ' if $name eq '';
            push @vals, $name;
        }
        if ( $ch eq "\t" ) {
            $newidx = 0;
            for my $i ( 0 .. $#vals ) {
                $newidx++;
                last if $vals[ $newidx - 1 ] eq $actval;
            }
            $newidx = 0 if ( $newidx > $#vals );
        }
        elsif ( $ch == KEY_BTAB ) {
            $newidx = $#vals;
            for my $i ( 0 .. $#vals ) {
                $newidx--;
                last if $vals[ $newidx + 1 ] eq $actval;
            }
            $newidx = $#vals if ( $newidx < 0 );
        }
        if ( $form->{fields}[$fi]{type} & $BOOLEAN ) {
            set_field_buffer( current_field($cform), 0,
                ralign( $vals[$newidx], $BOOLEAN_FIELD_SIZE ) );
        }
        else {
            set_field_buffer( current_field($cform), 0,
                $vals[$newidx] );
        }
        form_driver( $cform, REQ_END_FIELD );
        $check_val_changes->();
    }
    else {
        trace("unknown list_cmd action/type \"$action\"/\"$type\"");
        beep();
    }
    return;
}

sub form_value_list {
    my ( $form, $cform, $win, $es, $check_val_changes ) = @_;

    curs_set($OFF) if $ctx->{cfg}{HIDE_CURSOR};
    my $ci = int( field_index( current_field($cform) ) / 7 );
    if ( $form->{fields}[$ci]{list_cmd} ) {
        my $val;
        my @list          = ();
        my @err           = ();
        my $multi_val_sep = $form->{fields}[$ci]{list_sep};
        my ( $action, $type, $args ) = split /:/,
          $form->{fields}[$ci]{list_cmd}, 3;
        if ( lc($action) eq 'command' ) {
            my ( $wpan, $wwin ) = open_wait_msg;
            trace( "raw list_cmd: \"$args\"", $LOG_LIST_CMD );

            foreach my $i ( 0 .. $#{ $form->{fields} } ) {
                my $id  = $form->{fields}[$i]{id};
                my $val = '';
                unless ( $form->{fields}[$i]{type} & $BOOLEAN ) {
                    $val =
                      field_buffer( $form->{fields}[$i]{ptr}, 0 );
                    $val =~ s/^\s+//;
                    $val =~ s/\s+$//;
                }
                $args =~ s/%\{$id\}/$val/g;
            }
            trace(
"list_cmd after field(s) value substitution: \"$args\"",
                $LOG_LIST_CMD
            );

            unless (
                exec_command( $args, $form->{path}, \@list, \@err ) )
            {
                trace( "error generating list:", $LOG_LIST_CMD );
                trace( "\"" . join( "\"\n\"", @err ) . "\"",
                    $LOG_LIST_CMD );
                if (@err) {
                    ($es) = do_list( $win, 'Error', 'display',
                        \@err, undef );
                }
                else {
                    # issue #1: a failed list_cmd that wrote
                    # nothing to stderr must not be handed to
                    # do_list as an empty list.
                    disp_msg( $win, $LIST_CMD_ERR_MSG,
                        $LIST_CMD_ERR_TITLE );
                }
                @list = ();
            }
            close_wait_msg( $wpan, $wwin, $win );
        }
        elsif ( lc($action) eq 'const' ) {
            $args =~ s/^ *"//;
            $args =~ s/" *$//;
            @list = split /" *, *"/, $args;
        }
        else {
            trace("unknown list_cmd action type \"$action\"");
        }
        if (@list) {
            my @selected = ();
            if ( $type eq 'multi-val' ) {
                $_ = field_buffer( current_field($cform), 0 );
                s/\s+$//;
                @selected = split /$multi_val_sep/;
            }
            ( $es, @selected ) =
              do_list( $win, $form->{fields}[$ci]{label},
                $type, \@list, \@selected );
            $val = join( $multi_val_sep, @selected );
            if ( ( $es // 0 ) == $ES_EXIT ) {
                return ( $es, $TRUE );
            }
        }
        else {
            trace( "empty list by list_cmd", $LOG_LIST_CMD );
            disp_msg( $win, $EMPTY_LIST_MSG, $EMPTY_LIST_TITLE );
        }
        if ( $form->{fields}[$ci]{type} & $BOOLEAN ) {
            $val = ralign( $val, $BOOLEAN_FIELD_SIZE );
        }
        if ( $es != $ES_CANCEL and $es != $ES_EXIT ) {
            set_field_buffer( current_field($cform), 0, $val );
            $check_val_changes->();
            form_driver( $cform, REQ_END_FIELD );
        }
    }
    else {
        disp_msg( $win, $NULL_LIST_MSG, $NULL_LIST_TITLE );
    }
    curs_set($ON) if $ctx->{cfg}{HIDE_CURSOR};
    return ( $es, $FALSE );
}

sub run_form_submit {
    my (
        $form,            $cform,          $win,
        $title,           $formname,       $es,
        $sync_fields_val, $prepare_action, $save_persistent
    ) = @_;

    my ( $action, $args, $wait_key, @actopts );
    my ( $i, $id, $val, $called_form );

    $sync_fields_val->();

    my $empty_required = $NO;
    foreach $i ( 0 .. $#{ $form->{fields} } ) {
        if (    $form->{fields}[$i]{required}
            and $form->{fields}[$i]{value} eq '' )
        {
            $empty_required = $YES;
            curs_set($OFF) if $ctx->{cfg}{HIDE_CURSOR};
            disp_msg(
                $win,
                "\"$form->{fields}[$i]{label}\" $ERR_EMPTY_FIELD_MSG",
                $ERR_EMPTY_FIELD_TITLE
            );
            curs_set($ON) if $ctx->{cfg}{HIDE_CURSOR};
            last;
        }
    }

    unless ($empty_required) {
        my $act = CCFE::Action::parse( $form->{action} );
        $action  = $act->{verb};
        $args    = $act->{args};
        @actopts = @{ $act->{opts} };

        my ( $aborted, $opt_es );
        ( $wait_key, $aborted, $opt_es ) =
          apply_action_opts( \@actopts, $win, $CONFIRM_TITLE );
        $es = $opt_es if defined $opt_es;
        $action = 'ABORTED' if $aborted;
        $save_persistent->();
        if ( $action eq 'run' ) {
            $prepare_action->( \$args );

            trace("action: \"$action\":\n");
            trace( "\n\n" . '-' x 80,
                $LOG_ACTION_CMD + $LOG_NORMAL );
            my ( $ss, $mm, $hh, $dd, $mt, $yy ) = localtime(time);
            trace(
                "DATE  : "
                  . sprintf( "%02d/%02d/%d, %02d:%02d:%02d\n",
                    $dd, ++$mt, 1900 + $yy, $hh, $mm, $ss )
                  . "SCREEN: $title  [$formname]\n"
                  . "DESCR : Action executed",
                $LOG_ACTION_CMD + $LOG_NORMAL
            );
            trace( '-' x 80, $LOG_ACTION_CMD + $LOG_NORMAL );
            trace( $args,    $LOG_ACTION_CMD + $LOG_NORMAL );
            $es =
              run_browse( $title, $args, $formname, $form->{path} );
            curs_set($ON) if $ctx->{cfg}{HIDE_CURSOR};
        }
        elsif ( $action eq 'form' ) {
            foreach $i ( 0 .. $#{ $form->{fields} } ) {
                $id  = $form->{fields}[$i]{id};
                $val = $form->{fields}[$i]{value};
                $val  =~ s/^\s+//;
                $val  =~ s/\s+$//;
                $args =~ s/%\{$id\}/$val/g;
            }

            ( $called_form, $args ) = split /\s+/, $args, 2;
            $args =~ s/^\s+//;
            $args =~ s/\s+$//;
            trace( "call form \"$called_form\", args \"$args\"",
                $LOG_ACTION_CMD );
            $es =
              do_form( $called_form, $title, split /\s+/, $args );
            if ( $es and $es < $ES_USER_REQ ) {
                trace(
                    "WARNING: $es_str[$es] reading form \"$called_form\""
                );
                curs_set($OFF) if $ctx->{cfg}{HIDE_CURSOR};
                disp_msg(
                    $win,
                    "$es_str[$es] $LOAD_FORM_ERR_MSG \"$called_form\"",
                    $FORM_ERR_TITLE
                );
                curs_set($ON) if $ctx->{cfg}{HIDE_CURSOR};
            }
        }
        elsif ( $action eq 'system' ) {
            $prepare_action->( \$args );
            if ( restricted_denies_verb( 'system', $args ) ) {
                disp_msg( $win, $RESTRICTED_MSG, $RESTRICTED_TITLE );
            }
            else {
                call_system( $wait_key, $args );
            }
        }
        elsif ( $action eq 'exec' ) {
            $prepare_action->( \$args );
            if ( restricted_denies_verb( 'exec', $args ) ) {
                disp_msg( $win, $RESTRICTED_MSG, $RESTRICTED_TITLE );
            }
            else {
                $ctx->{state}{exec_args} = $args;
            }
        }
        else {
            trace("unknown form action type \"$action\"");
        }
        $LOG_REQUESTED = $NO;
    }

    return $es;
}

sub do_form {
    my ( $formname, $title, @argv ) = @_;

    my @fset;
    my @fp;    # field pointers; M7 Phase 3: per-call lexical, not a `local`
    my ( $es, $rows, $cols, $i, $nfields, $field, $ch, $fsub, $y, $npages );
    my $cform;
    my ($pan);
    my ( $win, $mwinr, $dots, $c );
    my ( $exit_id, $exit_descr );
    my (
        $id,     $all_ids, $label,  $len, $type, $default,
        $hidden, $hscroll, $script, $val, $form_dir
    );
    my ($fpad);
    # M7 de-globalisation (Phase 1): the per-form field-value map is a per-call
    # lexical, not a shared global -- this preserves the old `local %field_vals`
    # recursion semantics (a nested screen gets its own) and is threaded into
    # the nested load_persistent() explicitly rather than via dynamic scope.
    my $field_vals = {};
    my %form;    # the form; M7 Phase 3: per-call lexical filled by load_form,
                 # captured by the helper closures above and resize_form below
    my ( @fields_to_remove, @fields_to_enable, @fields_to_disable );

    # M7 de-globalisation (Phase 3): the form's nested helpers are anonymous
    # closures, not named subs, so each do_form call's helpers capture that
    # call's own form state ($cform/@fp/%form) -- a named sub would bind the
    # first call's copy ("won't stay shared").  Forward-declared so any future
    # mutual reference resolves; assigned below.
    my (
        $sync_fields_val,   $set_field_attr, $set_field_active_attr,
        $check_val_changes, $prepare_action, $save_persistent,
        $load_persistent
    );

    $sync_fields_val = sub {
        form_driver( $cform, REQ_VALIDATION );
        foreach my $i ( 0 .. $#{ $form{fields} } ) {
            $form{fields}[$i]{value} =
              field_buffer( $form{fields}[$i]{ptr}, 0 );
            $form{fields}[$i]{value} =~ s/\s+$//;
            if ( $form{fields}[$i]{type} & $BOOLEAN ) {
                $form{fields}[$i]{value} =~ s/^\s+//;
            }
        }
    };

    $set_field_attr = sub {
        my $lptr = $fp[ field_index( current_field($cform) ) - 6 ];
        my $vptr = $fp[ field_index( current_field($cform) ) ];
        my $fidx = int( field_index( current_field($cform) ) / 7 );
        set_field_fore( $lptr, $ctx->{cfg}{labelFg} );
        set_field_back( $lptr, $ctx->{cfg}{labelBg} );
        set_field_fore( $vptr, $form{fields}[$fidx]{valueFg} );
        set_field_back( $vptr, $form{fields}[$fidx]{valueBg} );
    };

    $set_field_active_attr = sub {
        my ( $bg, $fg );
        my $fidx = int( field_index( current_field($cform) ) / 7 );
        if ( $ctx->{cfg}{SHOW_CHGD_FIELDS} and $form{fields}[$fidx]{changed} ) {
            $fg = $ctx->{cfg}{acf_valueFg};
            $bg = $ctx->{cfg}{acf_valueBg};
        }
        else {
            $fg = $ctx->{cfg}{af_valueFg};
            $bg = $ctx->{cfg}{af_valueBg};
        }
        set_field_fore( $fp[ field_index( current_field($cform) ) - 6 ],
            $ctx->{cfg}{af_labelFg} );
        set_field_back( $fp[ field_index( current_field($cform) ) - 6 ],
            $ctx->{cfg}{af_labelBg} );
        set_field_fore( $fp[ field_index( current_field($cform) ) ], $fg );
        set_field_back( $fp[ field_index( current_field($cform) ) ], $bg );
    };

    $check_val_changes = sub {
        form_driver( $cform, REQ_VALIDATION );
        my $curr_val = field_buffer( current_field($cform), 0 );
        $curr_val =~ s/\s+$//;
        my $fi = int( field_index( current_field($cform) ) / 7 );
        if ($ctx->{cfg}{SHOW_CHGD_FIELDS}) {
            if ( $curr_val ne $form{fields}[$fi]{value} ) {
                $form{fields}[$fi]{changed} = $YES;
                set_field_fore( $fp[ field_index( current_field($cform) ) ],
                    $ctx->{cfg}{acf_valueFg} );
                set_field_back( $fp[ field_index( current_field($cform) ) ],
                    $ctx->{cfg}{acf_valueBg} );
                $form{fields}[$fi]{valueFg} = $ctx->{cfg}{cf_valueFg};
                $form{fields}[$fi]{valueBg} = $ctx->{cfg}{cf_valueBg};
            }
            else {
                set_field_fore( $fp[ field_index( current_field($cform) ) ],
                    $ctx->{cfg}{af_valueFg} );
                set_field_back( $fp[ field_index( current_field($cform) ) ],
                    $ctx->{cfg}{af_valueBg} );
                $form{fields}[$fi]{valueFg} = $ctx->{cfg}{valueFg};
                $form{fields}[$fi]{valueBg} = $ctx->{cfg}{valueBg};
            }
        }
    };

    $prepare_action = sub {
        my ($action_ref) = @_;

        my ( $id, $val );

        foreach my $i ( 0 .. $#{ $form{fields} } ) {
            $val = '';
            $id  = $form{fields}[$i]{id};

            # Expose every field's raw value as an environment variable so an
            # action command can read it safely (e.g. "$CCFE_FIELD_INFILE")
            # instead of interpolating %{INFILE} into a shell string, which is
            # a command-injection vector.  See REFACTOR.md section 2.
            if ( defined $id and $id ne '' ) {
                my $raw = $form{fields}[$i]{value};
                $raw = '' unless defined $raw;
                $raw =~ s/^\s+//;
                $raw =~ s/\s+$//;
                $ENV{"CCFE_FIELD_$id"} = $raw;
            }

            unless ( !$form{fields}[$i]{changed}
                and $form{fields}[$i]{ignore_unchgd} )
            {
                if ( $form{fields}[$i]{type} == $BOOLEAN ) {
                    my ( $yes_opt, $no_opt ) = split /\s*,\s*/,
                      $form{fields}[$i]{option}, 2;
                    if ( $form{fields}[$i]{value} eq $BFIELD_YES ) {
                        $val = " $yes_opt";
                    }
                    elsif ( defined($no_opt) ) {
                        $val = " $no_opt";
                    }
                }
                elsif ( $form{fields}[$i]{type} == $NULLBOOLEAN ) {
                  SWITCH: {
                        if ( $form{fields}[$i]{value} eq $BFIELD_YES ) {
                            $val = " $form{fields}[$i]{option} y";
                            last SWITCH;
                        }
                        if ( $form{fields}[$i]{value} eq $BFIELD_NO ) {
                            $val = " $form{fields}[$i]{option} n";
                            last SWITCH;
                        }
                    }
                }
                else {
                    $val = $form{fields}[$i]{value};
                    $val =~ s/^\s+//;
                    $val =~ s/\s+$//;
                    if ( $form{fields}[$i]{option} and $val ne '' ) {
                        my $option = $form{fields}[$i]{option};
                        my $quote = substr( $option, -1, 1, '' )
                          if $option =~ /(['"])$/;
                        my $sep = ( $option !~ /=$/ ) ? ' ' : '';
                        $val = "$quote$val$quote" if $quote;
                        if ( $val =~ /\s+/ and !$quote ) {
                            my $vals = '';
                            foreach $s ( split /\s+/, $val ) {
                                $vals .= $option . $sep . "$s ";
                            }
                            $val = $vals;
                        }
                        else {
                            $val = $option . $sep . "$val ";
                        }
                        $val =~ s/\s+$//;
                        $val = ' ' . $val if $val;
                    }
                }
            }
            $$action_ref =~ s/%\{$id\}/$val/g;
        }

        $$action_ref =~ s/^\s+//;
        $$action_ref =~ s/\s+$//;
    };

    $save_persistent = sub {
        my ( $fname, $hash, $c );

        $c = 0;
        foreach my $i ( 0 .. $#{ $form{fields} } ) {
            $c++ if ( $form{fields}[$i]{persist} );
        }
        trace("Found $c persistent field(s)");
        return 0 if $c == 0;

        $hash  = md5_hex("$ctx->{state}{SCREEN_DIR}/$formname$FORMEXT");
        $fname = "$PERS_DIR/$hash";

        foreach my $sd ( $PRIV_DIR, $PERS_DIR ) {
            unless ( -e $sd and -d $sd ) {
                if ( mkdir "$sd", 0700 ) {
                    trace("Created subdir $sd");
                }
                else {
                    my $errstr = $!;
                    trace("Error creating subdir $sd: $errstr");
                    disp_msg( $win, "$errstr $PERS_WRITE_ERROR_MSG",
                        $PERS_WRITE_ERROR_TITLE );
                    return 1;
                }
            }
        }

        eval {
            open( OUTF, ">$fname" ) or die("$!\n");
            print OUTF "# $ctx->{state}{SCREEN_DIR}/$formname$FORMEXT\n";
            foreach my $i ( 0 .. $#{ $form{fields} } ) {
                if ( $form{fields}[$i]{persist} ) {
                    $id  = $form{fields}[$i]{id};
                    $val = $form{fields}[$i]{value};
                    print OUTF "$id=$val\n";
                }
                $i++;
            }
            close(OUTF) or die("$!");
            chmod 0600, $fname;
        };
        if ($@) {
            chop($@);
            disp_msg( $win, "$@ $PERS_WRITE_ERROR_MSG",
                $PERS_WRITE_ERROR_TITLE );
            trace( "$@ error writing persistent data to $fname:",
                $LOG_FIELDS_VAL );
        }
        else {
            trace( "Persistent data written to $fname", $LOG_FIELDS_VAL );
        }
    };

    $load_persistent = sub {
        my ($field_vals) = @_;
        my @res = ();
        my ( $fname, $hash );

        $hash  = md5_hex("$ctx->{state}{SCREEN_DIR}/$formname$FORMEXT");
        $fname = "$PERS_DIR/$hash";
        eval {
            open( INF, "$fname" ) or die("$!\n");
            @res = <INF>;
            close(INF) or die("$!\n");
        };
        if ( int($!) != 2 ) {
            if ($@) {
                chop($@);
                trace("Error loading persistent data of form $fname: $@");
            }
            else {
                trace( "Loaded persistent data from $fname:", $LOG_FIELDS_VAL );
                foreach (@res) {
                    next if /^\s*#/;
                    chop;
                    my ( $id, $val ) = split /\s*=\s*/;
                    $field_vals->{$id} = $val;
                    trace( "  $id=\"$val\"", $LOG_FIELDS_VAL );
                }
            }
        }
    };

    unless ( $es = load_form( $formname, \$form_dir, \%form ) ) {
        undef(@fields_to_remove);
        undef(@fields_to_enable);
        undef(@fields_to_disable);
        my $ch_boolean = '';
        my $ch_string  = '[[:ascii:]]';
        my $ch_numeric = '[0-9\-\+,\.]';
        my $ch_set;

        $mwinr =
          $LINES -
          ( $FS_HEADER_ROWS +
              $FS_TOP_ROWS +
              $FS_BOTTOM_ROWS +
              $ctx->{cfg}{FS_FOOTER_ROWS} );
        $win = newwin( $LINES, $COLS, 0, 0 );
        $pan = new_panel($win);

        foreach $c ( 1 .. $#argv + 1 ) {
            trace(
                "argument %\{$FORM_ARGV_ID$c\} substituted with \"$argv[$c-1]\""
            );
            $form{init}   =~ s/%\{$FORM_ARGV_ID$c\}/$argv[$c-1]/g;
            $form{action} =~ s/%\{$FORM_ARGV_ID$c\}/$argv[$c-1]/g;
        }
        $form{init}   =~ s/%\{$FORM_ARGV_ID[1-9][0-9]*\}//g;
        $form{action} =~ s/%\{$FORM_ARGV_ID[1-9][0-9]*\}//g;

        if (
            run_form_init(
                \%form, $formname, $win, $field_vals,
                \@fields_to_remove, \@fields_to_enable, \@fields_to_disable
            )
          )
        {
            del_panel($pan);
            delwin($win);
            return;
        }
        $load_persistent->($field_vals);

        $lflags_size = $FIELD_LMARGIN;
        $rflags_size = $FIELD_RMARGIN;
        ( $npages, $all_ids ) = build_form_fields(
            \%form, $field_vals, \@fp, \@fset,
            \@fields_to_remove, \@fields_to_enable, \@fields_to_disable,
            $mwinr, $lflags_size, $rflags_size
        );

        # Keep the packed fields buffer alive for the form's lifetime:
        # new_form() stores the pointer without copying it (see do_menu() for
        # the full explanation).  Freed when this sub returns, after free_form().
        my $fields_buf = pack 'L!*', @fset;
        $cform = new_form($fields_buf);
        if ( $cform eq '' ) { fatal("do_form.new_form() failed") }

        scale_form( $cform, $rows, $cols );
        $fsub =
          derwin( $win, $mwinr, $COLS, $FS_HEADER_ROWS + $FS_TOP_ROWS, 0 );

        # Apply the screen background colour (a themed fg/bg pair gives the
        # panelled look) to the form window and its field area, matching what
        # do_menu does; the monochrome default (A_NORMAL) leaves it unchanged.
        bkgd( $win,  $ctx->{cfg}{MENU_SCREEN_ATTR} );
        bkgd( $fsub, $ctx->{cfg}{MENU_SCREEN_ATTR} );

        set_form_win( $cform, $win );
        set_form_sub( $cform, $fsub );

        form_opts_off( $cform, O_BS_OVERLOAD );
        keypad( $win, $ON );

        $form{action} =~ s/%{$ALL_FIELDS_IDS_TAG}/$all_ids/;
        $i = 0;
        while ( !$form{fields}[$i]{enabled} ) {
            $i++;
        }
        set_field_fore( $fp[ $i * 7 ], $ctx->{cfg}{af_labelFg} );
        set_field_back( $fp[ $i * 7 ], $ctx->{cfg}{af_labelBg} );
        set_field_fore( $fp[ $i * 7 + 6 ], $ctx->{cfg}{af_valueFg} );
        set_field_back( $fp[ $i * 7 + 6 ], $ctx->{cfg}{af_valueBg} );

        $title = $form{title} if $form{title};
        init_title( $win, $FS_HEADER_ROWS, $title );
        disp_page( $win, form_page($cform) + 1, $npages, 'form', $formname );
        init_top( $win, $NO, $FS_HEADER_ROWS, $FS_TOP_ROWS, @{ $form{top} } );
        init_footer( $win, $NO, $ctx->{cfg}{FS_FOOTER_ROWS}, @FSKeys );
        my $post_rc = post_form($cform);
        trace( "do_form: post_form => $post_rc ($npages page(s))", $LOG_NORMAL );
        if ($ovl_mode) {
            form_driver( $cform, REQ_OVL_MODE );
        }
        else {
            form_driver( $cform, REQ_INS_MODE );
        }
        form_driver( $cform, REQ_END_LINE );
        refresh($win);
        curs_set($ON) if $ctx->{cfg}{HIDE_CURSOR};

        # On a terminal resize, re-paginate the fields for the new height and
        # rebuild the window/form at the new $LINES/$COLS.  Field values are
        # preserved (the fields are never freed -- only re-laid-out).  Each
        # logical field is 7 curses fields sharing a row; move_field/
        # set_new_page need the fields disconnected, so the form is freed and
        # re-created around them.  Columns are kept (a horizontal re-layout of
        # right-aligned values is left to a future change).

        $es = $ES_NO_ERR;
        while ( $es != $ES_EXIT and !defined($ctx->{state}{exec_args}) ) {
          SWITCH: {
                my $fi    = int( field_index( current_field($cform) ) / 7 );
                my $ftype = $form{fields}[$fi]{type};
                if ( $ftype & $BOOLEAN ) {
                    $ch_set = $ch_boolean;
                    last SWITCH;
                }
                if ( $ftype & $STRING ) {
                    $ch_set = $ch_string;
                    last SWITCH;
                }
                if ( $ftype & $NUMERIC ) {
                    $ch_set = $ch_numeric;
                    last SWITCH;
                }
            }

            if ( data_behind($cform) ) {
                set_field_buffer(
                    $fp[ field_index( current_field($cform) ) - 3 ],
                    0, '<' );
            }
            else {
                set_field_buffer(
                    $fp[ field_index( current_field($cform) ) - 3 ],
                    0, $ctx->{cfg}{fval_delim}[0] );
            }
            if ( data_ahead($cform) ) {
                set_field_buffer(
                    $fp[ field_index( current_field($cform) ) - 2 ],
                    0, '>' );
            }
            else {
                set_field_buffer(
                    $fp[ field_index( current_field($cform) ) - 2 ],
                    0, $ctx->{cfg}{fval_delim}[1] );
            }

            $ch = getch($win);

            if ( $ch == KEY_UP or $ch == KEY_DOWN ) {
                $set_field_attr->();
                form_driver( $cform, REQ_NEXT_FIELD ) if $ch == KEY_DOWN;
                form_driver( $cform, REQ_PREV_FIELD ) if $ch == KEY_UP;
                $set_field_active_attr->();
                form_driver( $cform, REQ_END_LINE );
            }
            elsif ( $ch == KEY_LEFT ) {
                form_driver( $cform, REQ_LEFT_CHAR );
            }
            elsif ( $ch == KEY_RIGHT ) {
                form_driver( $cform, REQ_RIGHT_CHAR );
            }
            elsif ( $ch == KEY_NPAGE ) {
                $set_field_attr->();
                form_driver( $cform, REQ_NEXT_PAGE );
                redraw_form_page( $cform, $win );
                $set_field_active_attr->();
                form_driver( $cform, REQ_END_LINE );
                disp_page( $win, form_page($cform) + 1,
                    $npages, 'form', $formname );
                touchwin($win);
                refresh($win);
            }
            elsif ( $ch == KEY_PPAGE ) {
                if ( $npages > 1 ) {
                    $set_field_attr->();
                    form_driver( $cform, REQ_PREV_PAGE );
                    redraw_form_page( $cform, $win );
                    $set_field_active_attr->();
                    form_driver( $cform, REQ_END_LINE );
                    disp_page( $win, form_page($cform) + 1,
                        $npages, 'form', $formname );
                    touchwin($win);
                    refresh($win);
                }
            }
            elsif ( $ch == KEY_HOME ) {
                form_driver( $cform, REQ_BEG_FIELD );
            }
            elsif ( $ch == KEY_END ) {
                form_driver( $cform, REQ_END_FIELD );
            }
            elsif ( $ch == KEY_BACKSPACE ) {
                form_driver( $cform, REQ_DEL_PREV );
                $check_val_changes->();
            }
            elsif ( $ch == KEY_DC ) {
                form_driver( $cform, REQ_DEL_CHAR );
                $check_val_changes->();
            }
            elsif ( $ch == KEY_IC ) {
                if ($ovl_mode) {
                    $ovl_mode = $FALSE;
                    form_driver( $cform, REQ_INS_MODE );
                }
                else {
                    $ovl_mode = $TRUE;
                    form_driver( $cform, REQ_OVL_MODE );
                }
                disp_page( $win, form_page($cform) + 1,
                    $npages, 'form', $formname );
            }
            elsif ( $ch eq "\t" or $ch == KEY_BTAB ) {
                form_tab_cycle( \%form, $cform, $ch, $check_val_changes );
            }
            elsif ( $ch eq "\r" or $ch eq "\n" ) {
                $es =
                  run_form_submit( \%form, $cform, $win, $title, $formname,
                    $es, $sync_fields_val, $prepare_action, $save_persistent );
            }
            elsif ( $ch == $ctx->{cfg}{keys}{back}{code} or ord($ch) == 27 ) {
                $es = $ES_CANCEL;
                last;
            }
            elsif ( $ch == $ctx->{cfg}{keys}{list}{code} ) {
                my $brk;
                ( $es, $brk ) =
                  form_value_list( \%form, $cform, $win, $es,
                    $check_val_changes );
                if ($brk) {
                    $ch = $ctx->{cfg}{keys}{exit}{code};
                    last;
                }
            }
            elsif ( $ch == $ctx->{cfg}{keys}{show_action}{code} ) {
                $sync_fields_val->();
                my $args = $form{action};
                $args =~ s/^([a-zA-Z]+)\(?([a-zA-Z_,]*)\)?/$1/;
                if ($args) {
                    $prepare_action->( \$args );
                    my @cmd = split /\n/, $args;
                    curs_set($OFF) if $ctx->{cfg}{HIDE_CURSOR};
                    ($es) = do_list( $win, $SHOW_ACTION_TITLE, 'display', \@cmd,
                        undef );
                    curs_set($ON) if $ctx->{cfg}{HIDE_CURSOR};
                }
                else {
                    trace("ERROR: empty form action");
                    disp_msg( $win, $NULL_FACTION_MSG, $NULL_FACTION_TITLE );
                }
            }
            elsif ( $ch == $ctx->{cfg}{keys}{reset_field}{code} ) {
                my $fi = int( field_index( current_field($cform) ) / 7 );
                set_field_buffer( current_field($cform), 0,
                    field_buffer( current_field($cform), 1 ) );
                $form{fields}[$fi]{changed} = $NO;
                $form{fields}[$fi]{valueFg} = $ctx->{cfg}{valueFg};
                $form{fields}[$fi]{valueBg} = $ctx->{cfg}{valueBg};
                set_field_fore( $fp[ field_index( current_field($cform) ) ],
                    $ctx->{cfg}{af_valueFg} );
                set_field_back( $fp[ field_index( current_field($cform) ) ],
                    $ctx->{cfg}{af_valueBg} );
                form_driver( $cform, REQ_END_LINE );
            }
            elsif ( $ch == $ctx->{cfg}{keys}{save}{code} ) {
                form_save_fields( \%form, $win, $title, $formname,
                    $sync_fields_val );
            }
            elsif ( $ch == $ctx->{cfg}{keys}{shell_escape}{code} ) {
                if ( restricted_denies_shell() ) {
                    ;    # disabled in RESTRICTED mode (also off the key bar)
                }
                elsif ( valid_shell($ctx->{cfg}{USER_SHELL}) ) {
                    call_shell;
                    refresh($win);
                }
                else {
                    disp_msg( $win, $BAD_SHELL_MSG, $BAD_SHELL_TITLE );
                }
            }
            elsif ( $ch == KEY_RESIZE ) {
                ( $win, $fsub, $pan, $cform, $fields_buf, $npages, $mwinr )
                  = resize_form( \%form, \@fp, $win, $fsub, $pan, $cform,
                    $fields_buf, $rflags_size, $title, $formname,
                    $ovl_mode );
            }
            elsif ( $ch == $ctx->{cfg}{keys}{redraw}{code} ) {
                clearok( curscr, 1 );
                refresh(curscr);
            }
            elsif ( $ch == $ctx->{cfg}{keys}{exit}{code} ) {
                $es = $ES_EXIT;
                last;
            }
            elsif ( $ch >= KEY_F(1) and $ch <= KEY_F(12) ) {
                beep();
            }
            elsif ( $ch =~ /$ch_set/ ) {
                form_driver( $cform, REQ_VALIDATION );
                my $ci = int( field_index( current_field($cform) ) / 7 );
                if ( $form{fields}[$ci]{type} == $UCSTRING ) {
                    form_driver( $cform, ord( uc($ch) ) );
                }
                else {
                    form_driver( $cform, ord($ch) );
                }
                $check_val_changes->();
            }
            else {
                beep();
            }
        }

        unpost_form($cform);
        del_panel($pan);
        delwin($win);
        free_form($cform);
        map { free_field($_) } @fp;
        @fp   = ();
        @fset = ();
        %form = ();
        undef %form;

    }
    return $es;
}

sub round {
    my ($num) = @_;
    return sprintf( "%.0f", $num );
}

sub run_browse {
    my ( $title, $cmd, $save_fname, $extra_path ) = @_;

    local ($search_string);
    my ( $infh, $outfh, $errfh, $buff, $srbuff, $fh, $nr, $sel );
    my $is_partial = 0;
    my $outprev;
    my $errprev;
    my ( $out_lines, $err_lines );
    my ( $npages, $pg, $src );
    my @lines;
    my @ready;
    my ( $py, $c, $pan, $ch, $win, $hwin );
    my ( $es,         $status_fg_attr, $status_bg_attr );
    my ( $start_time, $end_time,       $exec_time );
    my ( $prev_path,  $prev_wdir );
    local ( $exec_ss, $exec_mm, $exec_hh );
    local ( $p, $mwin, $twin, $mwinr );
    my $cmd_descr = $title;

    sub get_search_buff {
        my ($row) = @_;
        my ( $buff, $chbuff, $row1, $c, $ln );

        $buff = '';
        $row1 = $row + ( $row < $ctx->{state}{pad_lines} ? 1 : 0 );
        for $ln ( $row .. $row1 ) {
            for $c ( 0 .. $COLS - 1 ) {
                inchnstr( $p, $ln, $c, $chbuff, 1 );
                $buff .= $chbuff;
            }
        }
        return $buff;
    }

    sub search_next {
        my ($row_ptr) = @_;
        my ( $buff, $pos0, $prev_row );

        $prev_row = $$row_ptr;
        $pos0     = -1;
        while ( $$row_ptr <= $ctx->{state}{pad_lines} and $pos0 <= 0 ) {
            $$row_ptr++;
            $buff = get_search_buff($$row_ptr);
            $buff =~ m/$search_string/g;
            $pos0 = pos($buff) - length($search_string);
            $pos0 = -1 if ( $pos0 > $COLS );
        }
        if ( $$row_ptr > $ctx->{state}{pad_lines} ) {
            $$row_ptr = $prev_row;
            disp_msg( $p, $FOUND_NONE_MSG, $FOUND_NONE_TITLE );
        }
    }

    sub search_all {
        my ( $buff, $pos0, $row, $nfound );

        $nfound = 0;
        for $row ( 0 .. $ctx->{state}{pad_lines} ) {
            $pos0 = -1;
            $buff = get_search_buff($row);
            do {
                $buff =~ m/$search_string/g;
                $pos0 = pos($buff) - length($search_string);
                $pos0 = -1 if ( $pos0 > $COLS );
                if ( $pos0 >= 0 ) {
                    $nfound++;
                    chgat( $p, $row, $pos0, length($search_string), A_REVERSE,
                        0, 0 );
                    if ( $pos0 + length($search_string) >= $COLS ) {
                        chgat( $p, $row + 1, 0,
                            $pos0 + length($search_string) - $COLS,
                            A_REVERSE, 0, 0 );
                    }
                }
            } while ( $pos0 >= 0 );
        }
        if ( !$nfound and ( $ctx->{state}{pad_lines} <= $mwinr ) ) {
            disp_msg( $p, $FOUND_NONE_MSG, $FOUND_NONE_TITLE );
        }
    }

    sub load_pad {
        my ( $src, $buff );
        my $c = 0;

        move( $p, 0, 0 );
        seek( $tmpfh, 0, 0 );
        while ( defined( $buff = <$tmpfh> ) and $c <= $ctx->{state}{pad_lines} )
        {
            $c++;
            ( $src, $buff ) = split /:/, $buff, 2;
            if ( length($buff) == $COLS + 1 ) {
                chop($buff);
                $ctx->{state}{pad_lines}--;
            }
            if ( $src eq $RS_STDOUT_ID ) {
                attrset( $p, $ctx->{cfg}{RS_STDOUT_ATTR} );
            }
            elsif ( $src eq $RS_STDERR_ID ) {
                attrset( $p, $ctx->{cfg}{RS_STDERR_ATTR} );
            }
            elsif ( $src eq $RS_INFO_ID ) {
                attrset( $p, $ctx->{cfg}{RS_INFO_ATTR} );
            }
            addstr( $p, $buff );
        }
    }

    $ctx->{state}{child_es} = 0;

    if ( $ctx->{cfg}{LAYOUT} == $SIMPLE ) {
        $status_fg_attr = A_NORMAL;
        $status_bg_attr = A_NORMAL;
    }
    else {
        $status_fg_attr = A_REVERSE;
        $status_bg_attr = A_REVERSE;
    }

    $prev_path = $ENV{PATH};
    $prev_wdir = getcwd();
    chdir "$ctx->{state}{SCREEN_DIR}";
    trace( "Changed CWD from $prev_wdir to " . getcwd() );
    $ENV{PATH} = sprintf "%s%s:.", $MAIN_PATH, $MAIN_PATH ? ":$ctx->{cfg}{PATH}" : '';
    if ($extra_path) {
        my @dirs = split /:/, $extra_path;
        foreach $i ( 0 .. $#dirs ) {
            $dirs[$i] = "$ctx->{state}{SCREEN_DIR}/$dirs[$i]" unless $dirs[$i] =~ /^\//;
        }
        $extra_path = join( ':', @dirs );
    }
    $ENV{PATH} .= ":$extra_path" if $extra_path;
    $ENV{COLUMNS} = $COLS;
    trace( "PATH=\"$ENV{PATH}\"", $LOG_SYSCALL_ENV );
    trace("run \"$cmd\"");

    $mwinr = $LINES -
      ( $RS_HEADER_ROWS + $RS_TOP_ROWS + $RS_BOTTOM_ROWS + $ctx->{cfg}{RS_FOOTER_ROWS} );
    $win = newwin( $LINES, $COLS, 0, 0 );
    $mwin = subwin( $win, $mwinr, $COLS, $RS_HEADER_ROWS + $RS_TOP_ROWS, 0 );
    $hwin = subwin( $win, $RS_HEADER_ROWS, $COLS, 0,               0 );
    $twin = subwin( $win, $RS_TOP_ROWS,    $COLS, $RS_HEADER_ROWS, 0 );
    $pan  = new_panel($win);
    bkgd( $win, $ctx->{cfg}{MENU_SCREEN_ATTR} );    # themed screen background (panel look)

    init_title( $hwin, $RS_HEADER_ROWS, $RB_TITLE );
    init_footer( $win, $NO, $ctx->{cfg}{RS_FOOTER_ROWS}, qw(int) );

    scrollok( $mwin, 1 );
    keypad( $mwin, $ON );
    nodelay( $mwin, 1 );

    bkgd( $twin, $status_bg_attr );
    addstr( $twin, 0, 0, "Status: $RB_RUNNING_MSG" );
    refresh($win);
    refresh($mwin);

    my $save_crsr = curs_set($OFF);
    curs_set($ON);

    $start_time = time;
    $errfh      = gensym();
    eval { $cpid = open3( $infh, $outfh, $errfh, $ctx->{cfg}{OPEN3_SHELL}, '-c', $cmd ); };
    fatal($@) if $@;
    trace("successfully forked child PID $cpid");
    $sel = IO::Select->new;
    $sel->add( $outfh, $errfh );

    $tmpfh = tempfile( 'ccfeXXXXX', DIR => '/tmp' );
    if ( !defined($tmpfh) ) {
        fatal("Error creating temporary file: $!");
    }
    trace( "----BEGIN OUTPUT" . '-' x 54, $LOG_ACTION_OUT );
    print $tmpfh "$RS_INFO_ID:\n";
    addstr( $mwin, "\n" );
    refresh($mwin);
    $ctx->{state}{pad_lines} = 1;

    $err_lines = $out_lines = 0;
    while ( @ready = $sel->can_read ) {
        foreach $fh (@ready) {
            $nr = sysread $fh, $srbuff, $SR_BUFF_SIZE;
            $srbuff =~ s/\r//g;
            if ( not defined $nr ) {
                fatal("Error from child $pid: $!");
            }
            elsif ( $nr == 0 ) {
                $sel->remove($fh);
                next;
            }
            else {
                if ( $fh == $outfh ) {
                    $src        = $RS_STDOUT_ID;
                    $buff       = ( $outprev // '' ) . $srbuff;
                    $is_partial = ( $buff !~ /\n$/ );
                    @lines      = split /\n/, $buff . ".";
                    $lines[$#lines] =~ s/\.$//;
                    pop @lines if !$lines[$#lines];
                    $outprev = $is_partial ? pop @lines : undef;
                    $out_lines += scalar @lines;
                    attrset( $mwin, $ctx->{cfg}{RS_STDOUT_ATTR} );
                }
                elsif ( $fh == $errfh ) {
                    $src        = $RS_STDERR_ID;
                    $buff       = ( $errprev // '' ) . $srbuff;
                    $is_partial = ( $buff !~ /\n$/ );
                    @lines      = split /\n/, $buff . ".";
                    $lines[$#lines] =~ s/\.$//;
                    pop @lines if !$lines[$#lines];
                    $errprev = $is_partial ? pop @lines : undef;
                    $err_lines += scalar @lines;
                    attrset( $mwin, $ctx->{cfg}{RS_STDERR_ATTR} );
                }
                else {
                    fatal("Unknown filehandle");
                }
            }
            foreach $s (@lines) {
                $ctx->{state}{pad_lines} += length($s) ? round( length($s) / $COLS + .5 ) : 1;
                print $tmpfh "$src:$s\n";
                trace( "$src:$s", $LOG_ACTION_OUT );
            }
            addstr( $mwin, $srbuff );
            refresh($mwin);
        }
    }
    if ( defined($outprev) ) {
        $out_lines++;
        $ctx->{state}{pad_lines} +=
          length($outprev) ? round( length($outprev) / $COLS + .5 ) : 1;
        print $tmpfh "$RS_STDOUT_ID:$outprev\n";
        trace( "$RS_STDERR_ID:$s", $LOG_ACTION_OUT );
        addstr( $mwin, $outprev );
    }
    if ( defined($errprev) ) {
        $err_lines++;
        $ctx->{state}{pad_lines} +=
          length($errprev) ? round( length($errprev) / $COLS + .5 ) : 1;
        print $tmpfh "$RS_STDERR_ID:$errprev\n";
        trace( "$RS_STDERR_ID:$s", $LOG_ACTION_OUT );
        addstr( $mwin, $errprev );
    }
    refresh($mwin);

    waitpid $cpid, 0;
    undef $cpid;
    $end_time  = time;
    $exec_time = $end_time - $start_time;

    $exec_ss = $exec_time % 60;
    $exec_time /= 60;
    $exec_mm = $exec_time % 60;
    $exec_hh = $exec_time / 60;

    trace( "----END OUTPUT" . '-' x 56, $LOG_ACTION_OUT );
    $ENV{PATH} = $prev_path;
    chdir "$prev_wdir";
    trace( "Restored CWD to " . getcwd() );
    if ($ctx->{cfg}{END_MARKER}) {
        print $tmpfh "$RS_INFO_ID:$ctx->{cfg}{END_MARKER}";
        $ctx->{state}{pad_lines}++;
    }

    if ( $ctx->{state}{pad_lines} > $ctx->{cfg}{MAX_PAD_LINES} ) {
        disp_msg( $win, $BIG_OUTPUT_MSG, $BIG_OUTPUT_TITLE );
        $ctx->{state}{pad_lines} = $ctx->{cfg}{MAX_PAD_LINES};
    }
    elsif ( $ctx->{state}{pad_lines} < $mwinr ) {
        $ctx->{state}{pad_lines} = $mwinr;
    }
    trace("Allocating ${pad_lines}x$COLS pad buffer");
    $p = newpad( $ctx->{state}{pad_lines}, $COLS );
    keypad( $p, 1 );
    load_pad;

    delwin($mwin);
    init_footer( $win, $NO, $ctx->{cfg}{RS_FOOTER_ROWS}, @RSKeys );
    curs_set($OFF) if $ctx->{cfg}{HIDE_CURSOR};
    addstr( $twin, 0, 0, "Status: " );
    attron( $twin, A_REVERSE ) if ( $ctx->{cfg}{LAYOUT} == $SIMPLE );
    addstr( $twin, $ctx->{state}{child_es} ? $RB_FAILED_MSG : $RB_OK_MSG );
    attroff( $twin, A_REVERSE ) if ( $ctx->{cfg}{LAYOUT} == $SIMPLE );
    addstr( $twin, $ctx->{state}{child_es} ? ' ' : '     ' );
    addstr(
        $twin,
        sprintf(
            "[ES=%d]   stdout: %d %s   " . "stderr: %d %s   %s: %02d:%02d:%02d",
            $ctx->{state}{child_es},  $out_lines,    $RB_LINES_MSG,
            $err_lines, $RB_LINES_MSG, $RB_TIME_MSG,
            $exec_hh,   $exec_mm,      $exec_ss
        )
    );
    clrtoeol($twin);
    refresh($twin);
    refresh($win);

    $search_string = '';
    $npages = round( $ctx->{state}{pad_lines} / $mwinr + ( $ctx->{state}{pad_lines} % $mwinr ? .5 : 0 ) );
    $py     = 0;
    while (1) {
        $pg = round( ( $py + 1 ) / $mwinr + ( ( $py + 1 ) % $mwinr ? .5 : 0 ) );
        disp_page( $hwin, $pg, $npages, 'browser', '' );
        refresh($hwin);
        move( $p, $py + $mwinr - 1, $COLS - 1 );
        prefresh(
            $p, $py, 0, $RS_HEADER_ROWS + $RS_TOP_ROWS,
            0, $RS_HEADER_ROWS + $RS_TOP_ROWS + $mwinr - 1,
            $COLS - 1
        );
        $ch = getch($p);
        if ( $ch == KEY_UP ) {
            $py-- if $py > 0;
        }
        if ( $ch == KEY_DOWN ) {
            $py++ if $py < $ctx->{state}{pad_lines} - $mwinr;
        }
        elsif ( $ch == KEY_PPAGE ) {
            my $c = $mwinr;
            while ( $py > 0 and $c > 0 ) {
                $py--;
                $c--;
            }
        }
        elsif ( $ch == KEY_NPAGE ) {
            my $c = $mwinr;
            while ( $py < $ctx->{state}{pad_lines} - $mwinr and $c > 0 ) {
                $py++;
                $c--;
            }
        }
        elsif ( $ch == KEY_HOME ) {
            $py = 0;
        }
        elsif ( $ch == KEY_END ) {
            $py = $ctx->{state}{pad_lines} - $mwinr;
            $py = 0 if $py < 0;
        }
        elsif ( $ch == $ctx->{cfg}{keys}{shell_escape}{code} ) {
            if ( restricted_denies_shell() ) {
                ;    # disabled in RESTRICTED mode (also off the key bar)
            }
            elsif ( valid_shell($ctx->{cfg}{USER_SHELL}) ) {
                curs_set($ON) if $ctx->{cfg}{HIDE_CURSOR};
                call_shell;
                curs_set($OFF) if $ctx->{cfg}{HIDE_CURSOR};
                refresh($win);
            }
            else {
                disp_msg( $win, $BAD_SHELL_MSG, $BAD_SHELL_TITLE );
            }
        }
        elsif ( $ch == $ctx->{cfg}{keys}{show_action}{code} ) {
            my @buff = split /\n/, $cmd;
            ($es) =
              do_list( $win, $SHOW_ACTION_TITLE, 'display', \@buff, undef );
        }
        elsif ( $ch == $ctx->{cfg}{keys}{back}{code} or ord($ch) == 27 ) {
            last;
        }
        elsif ( $ch == $ctx->{cfg}{keys}{exit}{code} ) {
            $es = $ES_EXIT;
            last;
        }
        elsif ( $ch == KEY_RESIZE ) {
            # Rebuild the full-screen frame and viewport for the new size.  The
            # output pad keeps its build-time wrap width (re-wrapping the
            # captured output to the new width is a refinement); the page count
            # follows the new height.
            $mwinr =
              $LINES - ( $RS_HEADER_ROWS + $RS_TOP_ROWS + $RS_BOTTOM_ROWS
                  + $ctx->{cfg}{RS_FOOTER_ROWS} );
            $mwinr = 1 if $mwinr < 1;
            my $rl = $LINES < 24 ? 24 : $LINES;
            my $rc = $COLS < 80  ? 80 : $COLS;
            del_panel($pan) if $pan;
            delwin($mwin)   if $mwin;
            delwin($hwin)   if $hwin;
            delwin($twin)   if $twin;
            delwin($win)    if $win;
            $win = newwin( $rl, $rc, 0, 0 );
            $mwin =
              subwin( $win, $mwinr, $rc, $RS_HEADER_ROWS + $RS_TOP_ROWS, 0 );
            $hwin = subwin( $win, $RS_HEADER_ROWS, $rc, 0, 0 );
            $twin = subwin( $win, $RS_TOP_ROWS, $rc, $RS_HEADER_ROWS, 0 );
            $pan  = new_panel($win);
            bkgd( $win, $ctx->{cfg}{MENU_SCREEN_ATTR} );
            init_title( $hwin, $RS_HEADER_ROWS, $RB_TITLE );
            init_footer( $win, $NO, $ctx->{cfg}{RS_FOOTER_ROWS}, @RSKeys );
            scrollok( $mwin, 1 );
            keypad( $mwin, $ON );
            $npages =
              round( $ctx->{state}{pad_lines} / $mwinr + ( $ctx->{state}{pad_lines} % $mwinr ? .5 : 0 ) );
            clearok( curscr, 1 );
            refresh($win);
        }
        elsif ( $ch == $ctx->{cfg}{keys}{redraw}{code} ) {
            clearok( curscr, 1 );
            refresh(curscr);
        }
        elsif ( $ch == $ctx->{cfg}{keys}{save}{code} ) {
            trim( \$cmd_descr );
            $save_fname = basename($save_fname);
            my $val;
            my @save_types = (
                "$SAVE_SIMPLE $SAVE_SIMPLE_DESCR",
                "$SAVE_DETAILED $SAVE_DETAILED_DESCR",
            );
            # The runnable-script save is an escape vector (writes a chmod +x
            # #!shell file): omit it in RESTRICTED mode.  Plain text saves stay.
            push @save_types, "$SAVE_SCRIPT $SAVE_SCRIPT_DESCR"
              unless $ctx->{cfg}{RESTRICTED};
            ( $es, $val ) =
              do_list( $win, $SAVE_TYPE_TITLE, 'single-val', \@save_types,
                undef );
            prefresh(
                $p, $py, 0, $RS_HEADER_ROWS + $RS_TOP_ROWS,
                0, $RS_HEADER_ROWS + $RS_TOP_ROWS + $mwinr - 1,
                $COLS - 1
            );
            if ($val) {
                my $fname = "$ENV{HOME}/$save_fname.out";
                $fname = "$ENV{HOME}/$save_fname." . basename($ctx->{cfg}{OPEN3_SHELL})
                  if ( $val eq $SAVE_SCRIPT );
                ( $es, $fname ) =
                  ask_string( $SAVE_FNAME_TITLE, $SAVE_FNAME_PROMPT, $fname );
                if ( ( $es // 0 ) == $ES_EXIT ) {
                    $ch = $ctx->{cfg}{keys}{exit}{code};
                    last;
                }
                refresh($win);
                if ( $es != $ES_CANCEL ) {
                    seek( $tmpfh, 0, 0 );
                    eval {
                        open( OUTF, ">$fname" ) or die('DIED');
                        if ( $val eq $SAVE_SIMPLE ) {
                            while (<$tmpfh>) {
                                print OUTF
                                  if s/(^$RS_STDOUT_ID:)|(^$RS_STDERR_ID:)//;
                            }
                        }
                        elsif ( $val eq $SAVE_DETAILED ) {
                            print OUTF '=' x 80 . "\n";
                            print OUTF "DESCRIPTION: $cmd_descr\n";
                            print OUTF "EXTRA PATH : ",
                              $extra_path ? $extra_path : 'none', "\n";
                            print OUTF "START TIME : ",
                              scalar localtime($start_time), "\n";
                            print OUTF "END TIME   : ",
                              scalar localtime($end_time), "\n";
                            printf OUTF "EXEC TIME  : %02dh %02dm %02ds\n",
                              $exec_hh, $exec_mm,
                              $exec_ss;
                            print OUTF "EXIT STATUS: ", $ctx->{state}{child_es}, "\n";
                            print OUTF "STDOUT     : ", $out_lines,
                              " line(s)\n";
                            print OUTF "STDERR     : ", $err_lines,
                              " line(s)\n";
                            print OUTF
                              "LINE PREFIX: std(O)ut  std(E)rr  (C)CFE\n";
                            print OUTF "COMMAND:\n$cmd\n";
                            print OUTF '=' x 80 . "\n";

                            while (<$tmpfh>) {
                                print OUTF or die('DIED');
                            }
                        }
                        elsif ( $val eq $SAVE_SCRIPT and !$ctx->{cfg}{RESTRICTED} ) {
                            print OUTF "#!$ctx->{cfg}{OPEN3_SHELL}\n";
                            print OUTF "# $cmd_descr\n";
                            print OUTF "$cmd\n";
                            chmod 0755, $fname;
                        }
                        close(OUTF) or die('DIED');
                        if ( $val eq $SAVE_SCRIPT ) {
                            chmod 0755, $fname;
                        }
                        else {
                            chmod 0644, $fname;
                        }
                    };
                    if ($@) {
                        prefresh(
                            $p,
                            $py,
                            0,
                            $RS_HEADER_ROWS + $RS_TOP_ROWS,
                            0,
                            $RS_HEADER_ROWS + $RS_TOP_ROWS + $mwinr - 1,
                            $COLS - 1
                        );
                        my $err = $!;
                        trace("WARNING: error opening file $fname: $err");
                        disp_msg( $win, "$err $SAVE_ERROR_MSG $fname",
                            $SAVE_ERROR_TITLE );
                    }
                }
            }
            if ( ( $es // 0 ) == $ES_EXIT ) {
                $ch = $ctx->{cfg}{keys}{exit}{code};
                last;
            }
        }
        elsif ( $ch eq '/' ) {
            ( $es, $search_string ) =
              ask_string( $SEARCH_PTRN_TITLE, $SEARCH_PTRN_PROMPT,
                $search_string );
            if ( ( $es // 0 ) == $ES_EXIT ) {
                $ch = $ctx->{cfg}{keys}{exit}{code};
                last;
            }
            refresh($win);
            prefresh(
                $p, $py, 0, $RS_HEADER_ROWS + $RS_TOP_ROWS,
                0, $RS_HEADER_ROWS + $RS_TOP_ROWS + $mwinr - 1,
                $COLS - 1
            );
            unless ( $es == $ES_CANCEL ) {
                load_pad if ($search_string);
                search_all;
                search_next( \$py ) if $ctx->{state}{pad_lines} > $mwinr;
            }
        }
        elsif ( $ch eq 'n' ) {
            search_next( \$py );
            $py = $ctx->{state}{pad_lines} - $mwinr if $py > $ctx->{state}{pad_lines} - $mwinr;
            $py = 0 if $py < 0;
        }
        else {
            beep();
        }
    }
    close($tmpfh);

    del_panel($pan);
    delwin($p);
    delwin($hwin);
    delwin($twin);
    delwin($win);
    curs_set($save_crsr);

    return $es;
}

sub get_shortcut {
    my ($shcut) = @_;

    foreach my $dir (@mf_path) {
        return $MENUEXT if -e "$dir/$shcut$MENUEXT";
        return $FORMEXT if -f "$dir/$shcut$FORMEXT";
    }
    return;
}

# Parse-check a menu or form by name (the `-k` linter).  Returns an exit code:
# 0 = parses cleanly, 1 = parse error, 2 = not found on the search path.
sub check_shortcut {
    my ($name) = @_;
    my $ext = get_shortcut($name);
    unless ($ext) {
        print STDERR
          "$CALLNAME: no menu or form \"$name\" on the search path\n";
        return 2;
    }
    my $is_menu = ( $ext eq $MENUEXT );
    my ( %menu, %form );    # filled by load_menu / load_form (M7 Phase 2-3)
    my $es =
      $is_menu
      ? load_menu( $name, \%menu )
      : load_form( $name, undef, \%form );
    if ( $es == $ES_NO_ERR ) {
        my $kind  = $is_menu ? 'menu' : 'form';
        my $title = $is_menu ? $menu{title} : $form{title};
        my $count =
          $is_menu
          ? scalar( @{ $menu{items}  || [] } )
          : scalar( @{ $form{fields} || [] } );
        my $unit = $is_menu ? 'item(s)' : 'field(s)';
        printf "OK: %s \"%s\" -- title \"%s\", %d %s\n", $kind, $name,
          ( defined $title ? $title : '' ), $count, $unit;
        return 0;
    }
    printf STDERR "ERROR: %s \"%s\": %s\n", ( $is_menu ? 'menu' : 'form' ),
      $name, ( $es_str[$es] || "parse error ($es)" );
    return 1;
}

# A field's type bitmask -> a stable name for machine-readable output.
sub field_type_name {
    my ($t) = @_;
    $t = 0 unless defined $t;
    return 'separator' if $t & $SEPARATOR;
    return 'ucstring'  if $t == $UCSTRING;
    return 'string'    if $t == $STRING;
    return 'numeric'   if $t == $NUMERIC;
    return 'boolean'   if $t & $BOOLEAN;        # also NULLBOOLEAN (6)
    return "type$t";
}

# `--dump NAME` / `-D NAME`: parse a menu or form (no terminal) and print it as
# JSON on stdout, for scripting, automation and the audit.  Exits like -k: 0 on
# success, 1 on a parse error, 2 when the name is not found.
sub dump_shortcut {
    my ($name) = @_;
    my $ext = get_shortcut($name);
    unless ($ext) {
        print STDERR
          "$CALLNAME: no menu or form \"$name\" on the search path\n";
        return 2;
    }
    require JSON::PP;
    my $is_menu = ( $ext eq $MENUEXT );
    my ( %menu, %form );    # filled by load_menu / load_form (M7 Phase 2-3)
    my $es =
      $is_menu
      ? load_menu( $name, \%menu )
      : load_form( $name, undef, \%form );
    if ( $es != $ES_NO_ERR ) {
        printf STDERR "ERROR: %s \"%s\": %s\n", ( $is_menu ? 'menu' : 'form' ),
          $name, ( $es_str[$es] || "parse error ($es)" );
        return 1;
    }

    my $out;
    if ($is_menu) {
        $out = {
            kind  => 'menu',
            name  => $name,
            title => $menu{title},
            top   => [ @{ $menu{top} || [] } ],
            items => [
                map { {
                    id     => $_->{id},
                    descr  => $_->{descr},
                    action => $_->{action},
                } } @{ $menu{items} || [] }
            ],
        };
    }
    else {
        $out = {
            kind   => 'form',
            name   => $name,
            title  => $form{title},
            top    => [ @{ $form{top} || [] } ],
            action => $form{action},
            fields => [
                map {
                    my $f = $_;
                    my %d = (
                        id       => $f->{id},
                        label    => $f->{label},
                        type     => field_type_name( $f->{type} ),
                        len      => defined $f->{len} ? $f->{len} + 0 : undef,
                        required => (
                            $f->{required}
                            ? JSON::PP::true()
                            : JSON::PP::false()
                        ),
                    );
                    $d{default} = $f->{default}
                      if defined $f->{default} && $f->{default} ne '';
                    $d{list_cmd} = JSON::PP::true() if $f->{list_cmd};
                    \%d;
                } @{ $form{fields} || [] }
            ],
        };
    }
    print JSON::PP->new->canonical->pretty->encode($out);
    return 0;
}

# Parse a plugin manifest (`<name>.plugin`): a single `plugin { ... }` block of
# `key = value` lines describing a packaged set of menus/forms.  Returns a
# hashref (keys lower-cased) or undef if the file has no recognisable name.
sub parse_manifest {
    my ($file) = @_;
    open( my $fh, '<', $file ) or return undef;
    my %m;
    while ( my $line = <$fh> ) {
        $line =~ s/#.*//;
        next unless $line =~ /^\s*([A-Za-z_]\w*)\s*=\s*(.*?)\s*$/;
        $m{ lc $1 } = $2;
    }
    close($fh);
    return undef unless defined $m{name} && length $m{name};
    return \%m;
}

# `--plugins`: list the installed plugins by scanning the object search path
# for `*.plugin` manifests, newest-wins per filename.  Human-readable, like -s.
sub list_plugins {
    my ( @found, %seen );
    for my $dir (@mf_path) {
        opendir( my $dh, $dir ) or next;
        for my $f ( sort readdir $dh ) {
            next unless $f =~ /\.plugin$/;
            next if $seen{$f}++;
            my $m = parse_manifest("$dir/$f");
            push @found, $m if $m;
        }
        closedir($dh);
    }
    unless (@found) {
        print "No CCFE plugins found on the object path.\n";
        exit 0;
    }
    printf "%-16s %-9s %s\n", 'PLUGIN', 'VERSION', 'DESCRIPTION';
    for my $m ( sort { ( $a->{name} || '' ) cmp( $b->{name} || '' ) } @found ) {
        printf "%-16s %-9s %s\n", $m->{name}, ( $m->{version} // '?' ),
          ( $m->{description} // '' );
        print "                 provides: $m->{provides}\n" if $m->{provides};
        if ( $m->{requires} ) {
            my @missing = grep { !cmd_in_path($_) } split ' ', $m->{requires};
            print "                 requires: $m->{requires}",
              ( @missing ? "  (missing: @missing)" : '' ), "\n";
        }
    }
    exit 0;
}

# True if a bare command name is found in $ctx->{cfg}{PATH} (for a manifest's `requires`).
sub cmd_in_path {
    my ($cmd) = @_;
    return 1 if $cmd =~ m{/} && -x $cmd;
    for my $d ( split /:/, ( $ENV{PATH} // '' ) ) {
        return 1 if -x "$d/$cmd";
    }
    return 0;
}

sub list_shortcuts {
    my @unique = ();
    my @all    = ();
    my @buff   = ();
    my ( $s, $dir, $val, $name, $fname, $fullpath, $nfound );
    my @sc_names;
    my %sc_descrs;
    my %sc_priv;

    for $dir (@mf_path) {
        opendir( DIR, $dir ) or next;    # search dirs (XDG/legacy) may not exist
        while ( $fname = readdir(DIR) ) {
            next if $fname =~ /^\.\.?$/;
            next if $fname !~ /($MENUEXT|$FORMEXT)$/;
            next if $fname eq "$REALNAME$MENUEXT";
            my @lines = ();
            $fullpath = "$dir/$fname";
            $fullpath .= "/$DMENU_DEF_FNAME" if ( -d $fullpath );
            push @all, $fullpath;
        }
        closedir(DIR);
    }

    @unique = @all;
    foreach $s (@all) {
        $s =~ s/($MENUEXT|$FORMEXT)$//;
        $nfound = scalar grep /^$s$/, @all;
        if ( $nfound == 2 ) {
            @unique = grep( !/^$s$FORMEXT$/, @unique );
        }
    }

    @all = @unique;
    foreach $s (@all) {
        ( $fname, undef, undef ) = fileparse( $s, ( $MENUEXT, $FORMEXT ) );
        $nfound = scalar grep /\/$fname($MENUEXT|$FORMEXT)$/, @all;
        if ( $nfound >= 2 ) {
            my $rmfname = "$PRIV_DIR/$CALLNAME/$fname";
            @unique = grep( !/^$rmfname/, @unique );
        }
    }

    foreach $s (@unique) {
        @lines = ();
        if ( open( INF, $s ) ) {
            while (<INF>) {
                next if /^\s*#/;
                push @lines, $_;
            }
            close(INF);
            $text = join( '', @lines );

            ( $val, undef, undef ) =
              extract_bracketed( $text, '{', '\s*title*\s*' );
            $val = '' unless defined $val;    # no/!malformed title block
            $val =~ s/^\{\s*//;
            $val =~ s/\s*\n?\s*\}$//;
            $val = 'N/A' if !$val;

            $s =~ s/\/$DMENU_DEF_FNAME$//;
        }
        else {
            print STDERR "$CALLNAME: error opening file $fullpath\n";
            print STDERR "$CALLNAME: $!\n";
            $val = "READ ERROR: $!";
        }
        ( $name, $dir, undef ) = fileparse( $s, ( $MENUEXT, $FORMEXT ) );
        push @buff, $name;
        $sc_descrs{$name} = $val;
        $sc_priv{$name} = ( $dir =~ /^$PRIV_DIR/ );
    }

    @sc_names = sort @buff;

    if (@unique) {
        my $maxllen = 8;
        my $maxrlen = 11;
        foreach my $i ( 0 .. $#sc_names ) {
            $maxllen = length( $sc_names[$i] )
              if length( $sc_names[$i] ) > $maxllen;
            $maxrlen = length( $sc_descrs{ $sc_names[$i] } )
              if length( $sc_descrs{ $sc_names[$i] } ) > $maxrlen;
        }

        eval
          "printf \"%${maxllen}s  %-${maxrlen}s\\n\",'Shortcut','Description'";
        print '-' x ${maxllen} . '  ' . '-' x ${maxrlen} . "\n";
        foreach my $i ( 0 .. $#unique ) {
            eval
"printf \"%${maxllen}s%1s %-${maxrlen}s\\n\",\$sc_names[\$i],(\$sc_priv\{\$sc_names[\$i]\} and \$MARK_PRIV_SHCUTS)?'~':'',\$sc_descrs\{\$sc_names[\$i]\}";
        }
    }
    else {
        print "$CALLNAME: no shortcut(s) available.\n";
    }
    exit;
}

sub HELP_MESSAGE {
    usage;
}

sub VERSION_MESSAGE {
    usage;
}

# When loaded with CCFE_TESTING set (e.g. `require`d from the test suite)
# stop here, before the interactive curses program runs, so the pure
# parser/utility subs above can be exercised headlessly.  Harmless in
# normal use: the condition is false, so the (otherwise illegal at file
# scope) return is never executed.
return 1 if $ENV{CCFE_TESTING};

$Getopt::Std::STANDARD_HELP_VERSION = $TRUE;
$Getopt::Std::OUTPUT_HELP_VERSION   = '';
%options                            = ();
# Accept the long forms `--dump NAME` / `--plugins` as aliases for `-D NAME` /
# `-P` (Getopt::Std itself only does single-letter options).
@ARGV = map { $_ eq '--dump' ? '-D' : $_ eq '--plugins' ? '-P' : $_ } @ARGV;
getopts( "vhsdcPD:k:l:", \%options ) or usage();
if ( defined $options{v} ) {
    my @months = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);
    my ( $dd, $mm, $yy ) = split /\//, $VERSION_DATE;

    print << "EOT";
$REALNAME version $VERSION ($months[$mm-1] $dd, $yy)
Copyright (C) $VERSION_YEAR Massimo Loschi

This program comes with ABSOLUTELY NO WARRANTY.  You may redistribute copies of
it under the terms of the GNU General Public License.
For more information about these matters, see the file named COPYING.
EOT
    exit 0;
}
# -l restricts the search to a single objects directory (explicit override).
# Environment overrides (CCFE_OBJ_DIR etc.) are applied up front in the path
# block and keep the normal search path, so they don't need handling here.
if ( defined( $options{l} ) ) {
    $OBJDIR  = $options{l};
    $WRKDIR  = $OBJDIR;
    @mf_path = ($OBJDIR);
}
usage()        if defined $options{h};
list_shortcuts if defined $options{s};
list_plugins   if defined $options{P};
print_config   if defined $options{c};
$DEBUG = $YES if defined $options{d};
$LANG_ID = get_lang_id;
load_msgs;
$es_str[$ES_NO_ERR]     = $ES_NO_ERR_MSG;
$es_str[$ES_SYNTAX_ERR] = $ES_SYNTAX_ERR_MSG;
$es_str[$ES_FOPEN_ERR]  = $ES_FOPEN_ERR_MSG;
$es_str[$ES_NOT_FOUND]  = $ES_NOT_FOUND_MSG;
$es_str[$ES_NO_ITEMS]   = $ES_NO_ITEMS_MSG;

# `-k NAME`: parse-check a menu or form without starting the terminal.  Uses
# the same headless parser the test suite does, so plugin authors and CI can
# validate .menu/.form files.  Exits 0 on success, 1 on a parse error, 2 if
# the name is not found on the search path.
exit check_shortcut( $options{k} ) if defined $options{k};
exit dump_shortcut( $options{D} )  if defined $options{D};

$ctx->{cfg}{keys} = {
    help => {
        code  => -1,
        label => $KEY_F1_LABEL
    },
    redraw => {
        code  => -1,
        label => $KEY_F2_LABEL
    },
    back => {
        code  => -1,
        label => $KEY_F3_LABEL
    },
    list => {
        code  => -1,
        label => $KEY_F4_LABEL
    },
    reset_field => {
        code  => -1,
        label => $KEY_F5_LABEL
    },
    show_action => {
        code  => -1,
        label => $KEY_F6_LABEL
    },
    sel_items => {
        code  => -1,
        label => $KEY_F7_LABEL
    },
    save => {
        code  => -1,
        label => $KEY_F8_LABEL
    },
    shell_escape => {
        code  => -1,
        label => $KEY_F9_LABEL
    },
    exit => {
        code  => -1,
        label => $KEY_F10_LABEL
    },
    do => {
        key   => 'Enter',
        label => $KEY_ENTER_LABEL
    },
    int => {
        key   => '^C',
        label => $KEY_INTR_LABEL
    },
    find => {
        key   => '/',
        label => $KEY_FIND_LABEL
    },
    find_next => {
        key   => 'n',
        label => $KEY_FNEXT_LABEL
    },
    sel_all => {
        key   => 'a',
        label => $KEY_SELALL_LABEL
    },
    unsel_all => {
        key   => 'u',
        label => $KEY_UNSELALL_LABEL
    }
};
@MSKeys = qw( help redraw back shell_escape exit do );
@FSKeys =
  qw( help redraw back list reset_field show_action save shell_escape exit do );
@RSKeys =
  qw( help redraw back show_action save shell_escape exit find find_next);

# Adopt the environment's character locale so ncursesw renders multi-byte
# (UTF-8) text by display column, in step with disp_width().  LC_CTYPE only --
# this must not change LC_NUMERIC (decimal point) or imply `use locale`.
POSIX::setlocale( POSIX::LC_CTYPE(), '' );

initscr;
$CURSES_ACTIVE = $YES;

# Once curses owns the screen, route Perl warnings to the log file rather than
# STDERR, where they would print over the display.  (`use warnings` -- M7 Phase
# 6 -- surfaces uninitialized-value notices on edge paths; they are harmless to
# behaviour but must not corrupt the TUI.)  Before initscr / in the headless
# --dump/-k paths $CURSES_ACTIVE is false, so warnings still reach STDERR.
$SIG{__WARN__} = sub {
    my ($w) = @_;
    return print STDERR $w unless $CURSES_ACTIVE;
    _log_write($w);    # TD-5: shares trace()'s persistent, autoflushed handle
    return;
};

# Safety net: if anything (even a die from deep in the Curses XS) tears the
# program down while the screen is in curses mode, restore the terminal so the
# user is not left needing `reset`.  endwin() is harmless if already called.
END { endwin() if $CURSES_ACTIVE }

if ( ( $COLS < 80 ) or ( $LINES < 24 ) ) {
    endwin();
    print STDERR "$CALLNAME: $ERR_LITTLE_SCREEN[0]\n";
    print STDERR "$CALLNAME: $ERR_LITTLE_SCREEN[1]\n";
    exit 1;
}

eval { new_form() };
if ( $@ =~ /not defined by your vendor/ ) {
    print STDERR "Curses was not compiled with form support.\n";
    exit 1;
}
eval { new_menu() };
if ( $@ =~ /not defined by your vendor/ ) {
    print STDERR "Curses was not compiled with menu support.\n";
    exit 1;
}

umask 0077;
$ENV{'CCFE_IWD'} = getcwd();
$ENV{'CCFE_LIB_DIR'} = $LIBDIR;    # kept for pre-v2 plugins
$ENV{'CCFE_OBJ_DIR'} = $OBJDIR;    # menus/forms (objects) dir
$ENV{'CCFE_BIN_DIR'} = $BINDIR;    # so actions can find sibling tools (ccfe-build)
$WRKDIR = "$OBJDIR/$CALLNAME" if !defined($WRKDIR);
my $shcut = $ARGV[0] ? $ARGV[0] : $REALNAME;
trace(
    sprintf "Starting $REALNAME called as \"$CALLNAME\", PID $$; Fastpath: %s",
    $shcut ne $REALNAME ? "\"$shcut\"" : 'NONE'
);

chdir "$WRKDIR";
trace( 'Changed CWD to ' . getcwd() );

$ctx->{cfg}{HIDE_CURSOR}      = $YES;
$ctx->{cfg}{SHOW_SCREEN_NAME} = $YES;
$ctx->{cfg}{INITIAL_OVL_MODE} = $NO;
# Mouse is opt-in (config `mouse = YES`): grabbing mouse events stops the
# terminal's own click-to-select text, which keyboard-first users may want.
$ctx->{cfg}{ENABLE_MOUSE}     = $NO;
$MOUSE_ON         = $NO;
$ctx->{cfg}{FIELD_PAD}        = 95;
$ctx->{cfg}{HFIELD_PAD}       = 42;
$ctx->{cfg}{SHOW_CHGD_FIELDS} = $YES;
$ctx->{cfg}{SHOW_FIELD_FLAGS} = $YES;
$ctx->{cfg}{SHOW_DOTS}        = $YES;
$ctx->{cfg}{MARK_NOACT_ITEMS} = $NO;
$ctx->{cfg}{MAX_PAD_LINES}    = 5000;
$ctx->{cfg}{RS_INFO_ATTR}     = A_REVERSE;
$ctx->{cfg}{RS_STDERR_ATTR}   = A_BOLD;
$ctx->{cfg}{RS_STDOUT_ATTR}   = A_NORMAL;
$ctx->{cfg}{END_MARKER}       = '';
$ctx->{cfg}{OPEN3_SHELL}      = '/bin/sh';
$ctx->{cfg}{USER_SHELL}       = ( getpwuid($>) )[8];
$ctx->{cfg}{fval_delim} = [ ' ', ' ' ];
$ctx->{cfg}{FIELD_VALUE_POS}  = -1;
# Auto value placement (FIELD_VALUE_POS == -1, NORMAL layout): the value column
# sits this many columns past the longest label on the page, instead of being
# right-aligned to the screen edge.  This keeps the dot run short and the form
# compact, so values stay on-screen on narrow terminals.
$FIELD_VALUE_GAP  = 4;
$ctx->{cfg}{RESTRICTED}        = $NO;
$ctx->{cfg}{RESTRICTED_ALLOW} = [];
$HAS_COLOR        = $NO;
# Menu/screen theme attributes.  Defaults preserve the historical monochrome
# look (overall screen normal, selected item reversed, bold title, reverse
# function-key highlight); a config (e.g. a SMIT-style instance) can set these
# to COLOR_PAIR(n) expressions for a colour UI.  $ctx->{cfg}{TITLE_ATTR} colours the header
# and $ctx->{cfg}{KEY_ATTR} the control keys in the footer bar; they apply to every screen
# (menus, forms, the output browser), since the title/footer are shared.
$ctx->{cfg}{MENU_SCREEN_ATTR} = A_NORMAL;
$ctx->{cfg}{MENU_ITEM_ATTR}   = A_NORMAL;
$ctx->{cfg}{MENU_SEL_ATTR}    = A_REVERSE;
$ctx->{cfg}{TITLE_ATTR}       = A_BOLD;
$ctx->{cfg}{KEY_ATTR}         = undef;     # undef = the original bkgd-relative highlight

if ( $res = load_config ) {
    trace("$es_str[$res] loading configuration file");
}
harden_child_env();
if ($ctx->{cfg}{RESTRICTED}) {
    # Hide the now-inert escape keys from the on-screen key bars; the key
    # handlers also enforce the policy, so this is defence in depth + UX.
    @MSKeys = grep { $_ ne 'shell_escape' } @MSKeys;
    @FSKeys = grep { $_ ne 'shell_escape' } @FSKeys;
    @RSKeys = grep { $_ ne 'shell_escape' } @RSKeys;

    # TD-1b: refuse menu/form object dirs the invoking user can write -- a
    # restricted user must not be able to drop a `run:` (unconstrained) menu
    # into ~/.local/share/ccfe or ~/.ccfe and have it loaded.  Only dirs the
    # user cannot write (system, root-owned) remain searched.  This assumes a
    # non-root user, as a kiosk/restricted login is; if it empties the path,
    # the system object dir must be made non-user-writable.
    my @kept = grep { !-w $_ } @mf_path;
    if ( @kept != @mf_path ) {
        my %keep = map { $_ => 1 } @kept;
        trace( "RESTRICTED: ignoring user-writable object dir \"$_\"" )
          for grep { !$keep{$_} } @mf_path;
        @mf_path = @kept;
    }

    trace(
        sprintf 'RESTRICTED mode ON: shell escape + save-to-script disabled; '
          . 'system:/exec: run shell-free, limited to [%s]',
        join( ', ', @{ $ctx->{cfg}{RESTRICTED_ALLOW} } ) || 'nothing'
    );
}

# Optional colour.  Purely additive: when the terminal supports colour (and
# NO_COLOR is not set and we are not in the SIMPLE monochrome layout) we
# enable it and pre-create the standard foreground colour pairs, so a
# configuration can reference COLOR_PAIR(n) in any of the *_attr settings
# (e.g. `stderr_attr = COLOR_PAIR(1) | A_BOLD`).  A theme can also ask for a
# foreground-over-background pair with `color_pair('white','blue')` (a panelled
# look): the *_attr eval ran at config-load time, before start_color(), so each
# such call only reserved a pair number -- init_dynamic_pairs() creates them
# here.  Otherwise nothing changes and the appearance is exactly as before.
# See CCFE::Theme / REFACTOR.md.
if ( has_colors() and !$ENV{NO_COLOR} and $ctx->{cfg}{LAYOUT} != $SIMPLE ) {
    start_color();
    eval { use_default_colors() };    # lets pairs use the terminal's own bg
    CCFE::Theme::init_standard_pairs();
    my $dyn = CCFE::Theme::init_dynamic_pairs();
    $HAS_COLOR = $YES;
    trace("colour enabled (standard pairs + $dyn fg/bg pair(s) created)");
}
if ( !$ctx->{cfg}{PERMIT_DEBUG} ) {
    trace('debugging disabled by configuration!');
    $DEBUG = $NO;
}
# Mouse (opt-in via `mouse = YES`): grab single and double left-clicks so a
# menu item can be pointed at (click selects, double-click activates).  A short
# double-click interval keeps a deliberate double-click responsive.
if ($ctx->{cfg}{ENABLE_MOUSE}) {
    my $old = 0;
    my $set = mousemask( BUTTON1_CLICKED() | BUTTON1_DOUBLE_CLICKED(), $old );
    if ($set) {
        mouseinterval(200);
        $MOUSE_ON = $YES;
        trace('mouse enabled (click to select, double-click to activate)');
    }
    else {
        trace('mouse requested but the terminal has none');
    }
}
trace("Using \"$ctx->{cfg}{USER_SHELL}\" for user shell escape");
trace("Using \"$ctx->{cfg}{OPEN3_SHELL}\" for commands execution");

if ( $ctx->{cfg}{keys}{back}{code} == -1 ) {
    $ctx->{cfg}{keys}{back}{code}  = KEY_F(10);
    $ctx->{cfg}{keys}{back}{key}   = 'F10';
    $ctx->{cfg}{keys}{back}{label} = ':Back';
    trace("\"Back\" fn key not defined - force F10=Back");
}

$ovl_mode       = $ctx->{cfg}{INITIAL_OVL_MODE};
$ASKS_FIELD_PAD = $ctx->{cfg}{FIELD_PAD};

if ( $shcut_type = get_shortcut($shcut) ) {
    noecho;
    curs_set($OFF) if $ctx->{cfg}{HIDE_CURSOR};

    # Run the interaction under a guard: should anything die uncaught from deep
    # in a menu/form (e.g. a Curses XS error), restore the terminal and report a
    # clean one-line message instead of dumping a Perl backtrace onto a screen
    # still in curses mode.  Expected outcomes (a normal exit, a bad object)
    # flow through $es as before.
    my $ok = eval {
      SWITCH: {
            $_ = $shcut_type;
            if (/$MENUEXT/) {
                ( $es, $id, $descr ) = do_menu($shcut);
                if ( $es and $es < $ES_USER_REQ ) {
                    trace("FATAL: $es_str[$es] while reading menu \"$shcut\"");
                }
                last SWITCH;
            }
            if (/$FORMEXT/) {
                $es = do_form($shcut);
                if ( $es and $es < $ES_USER_REQ ) {
                    trace("FATAL: $es_str[$es] while reading form \"$shcut\"");
                }
                last SWITCH;
            }
        }
        1;
    };
    if ( !$ok ) {
        my $err = $@ || 'unknown error';
        chomp $err;
        $err =~ s/ at \S+ line \d+\.?\s*$//;    # drop Perl's "at FILE line N"
        trace("FATAL: uncaught error during interaction: $@");
        endwin() if $CURSES_ACTIVE;
        $CURSES_ACTIVE = $NO;
        system("clear");
        print STDERR "$CALLNAME: internal error: $err\n";
        exit 1;
    }

    clear();
    refresh();
    endwin();
    system("clear") if $es == $ES_NO_ERR or $es >= $ES_USER_REQ;
    if ( defined($ctx->{state}{exec_args}) ) {
        chdir "$ctx->{state}{SCREEN_DIR}";
        trace( "Changed CWD from $prev_wdir to " . getcwd() );
        trace("exec \"$ctx->{state}{exec_args}\"");
        if ( $ctx->{cfg}{RESTRICTED} ) {
            my @argv = shellwords( $ctx->{state}{exec_args} );    # TD-1c
            exec { $argv[0] } @argv if @argv;
        }
        exec( $ctx->{state}{exec_args} );
    }
}
else {
    refresh();
    endwin();
    trace("Initial menu or form \"$shcut\" not found - Abort");
    print STDERR "$CALLNAME: $ERR_WRONG_FPATH[0] \"$shcut\".\n";
    print STDERR "$CALLNAME: $ERR_WRONG_FPATH[1]\n";
}
if ( $es and $es < $ES_USER_REQ ) {
    refresh();
    endwin();
    print STDERR "$CALLNAME: $es_str[$es] $ERR_LOAD_INITIAL_OBJ \"$shcut\"\n";
}

# Never let a stray libcurses error code (e.g. E_NOT_CONNECTED == -11, which
# would surface to the shell as exit status 245) leak out as our exit status.
# A negative or out-of-range $es means something internal went wrong; report it
# in the trace and exit with a clean, conventional code instead.
if ( !defined($es) ) {
    $es = $ES_NO_ERR;
}
elsif ( $es < 0 or $es > 255 ) {
    trace("internal: clamping out-of-range exit status \"$es\" to 1");
    $es = 1;
}
exit $es;
