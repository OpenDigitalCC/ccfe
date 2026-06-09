#!/usr/bin/perl
#
# Regression guard for issue #1 ("segfault on forms").
#
# Root cause: do_list() built a curses menu from an EMPTY item list; with
# no items current_item() is NULL and item_index(current_item(...)) dies
# with "argument 0 to Curses function 'item_index' is not a Curses item",
# segfaulting on some ncurses builds.  The empty list reached do_list via
# do_form()'s error branch when a field's list_cmd command failed without
# writing anything to stderr.
#
# Driving the real curses UI (pressing F2 on a failing list_cmd) needs a
# pseudo-terminal harness (libio-pty-perl / libexpect-perl) that is not a
# standard part of this build, so this test instead pins the three guards
# that make the crash unreachable.  It fails loudly if any of them is
# removed.  Replace with a pty-driven end-to-end test once Expect is
# available.
#
use strict;
use warnings;
use Test::More tests => 9;
use FindBin qw($Bin);

my $src = "$Bin/..";

sub slurp {
    my ($f) = @_;
    open( my $fh, '<', $f ) or die "open $f: $!";
    local $/;
    my $c = <$fh>;
    close($fh);
    return $c;
}

my $code = slurp("$src/ccfe.pl");
my $msgs = slurp("$src/msg/C/ccfe");

# 1. do_list bails out before building a menu when handed an empty list.
like(
    $code,
    qr/unless \s* \( \s* \@\$ilist_ref \s* \) \s* \{ [^}]*? disp_msg [^}]*? return \s+ \$ES_CANCEL/xs,
    'do_list has an empty-item-list guard that returns before menu creation'
);

# 2. The do_list position-message call site guards item_index against a
#    NULL current item.  (do_menu also calls item_index(current_item(...)),
#    but only on menus that load_menu() guarantees are non-empty, so the
#    crash never originated there -- hence a positive check here, not a
#    global "no raw call" assertion.)
like(
    $code,
    qr/\$cur_item\s*\?\s*item_index\(\s*\$cur_item\s*\)\s*:\s*-1/,
    'item_index in do_list is guarded against a NULL current item'
);

# 3. do_form's error branch only calls do_list when there is error text.
like(
    $code,
    qr/if\s*\(\s*\@err\s*\)\s*\{[^}]*?do_list\([^)]*?'display'/s,
    'do_form error branch guards do_list with "if (\@err)"'
);

# 4. The "command failed" message is declared and defined for i18n.
like( $code, qr/\bLIST_CMD_ERR_MSG\b/,
    'LIST_CMD_ERR_MSG is registered in the message id list' );
like( $msgs, qr/^LIST_CMD_ERR_MSG\s*=/m,
    'LIST_CMD_ERR_MSG is defined in msg/C/ccfe' );
like( $msgs, qr/^LIST_CMD_ERR_TITLE\s*=/m,
    'LIST_CMD_ERR_TITLE is defined in msg/C/ccfe' );

# 5. The dangling-items-buffer crash (the broader root cause of issue #1).
#    new_menu()/new_form() keep the packed pointer without copying it, so the
#    buffer must be held in a lexical that outlives the menu/form.  Guard that
#    no call site reverts to building the menu/form from an inline pack()
#    temporary, and that the retained-buffer form is what's used.  t/03 proves
#    the runtime effect; this fails fast at the source level.
unlike(
    $code,
    qr/new_(?:menu|form)\(\s*pack\b/,
    'no menu/form is built from an inline pack() temporary (dangling pointer)'
);
like(
    $code,
    qr/\$items_buf\s*=\s*pack\s+'L!\*'.*?new_menu\(\s*\$items_buf\s*\)/s,
    'menus keep the packed items buffer alive (new_menu($items_buf))'
);
like(
    $code,
    qr/\$fields_buf\s*=\s*pack\s+'L!\*'.*?new_form\(\s*\$fields_buf\s*\)/s,
    'forms keep the packed fields buffer alive (new_form($fields_buf))'
);
