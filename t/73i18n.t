#!/usr/bin/perl -w
use strict;
use File::Path;
BEGIN { require 't/tree.pl' };
use POSIX qw(setlocale LC_CTYPE);
setlocale (LC_CTYPE, $ENV{LC_CTYPE} = 'zh_TW.Big5')
    or plan skip_all => 'cannot set locale to zh_TW.Big5';
setlocale (LC_CTYPE, $ENV{LC_CTYPE} = 'en_US.UTF-8')
    or plan skip_all => 'cannot set locale to en_US.UTF-8';;

plan tests => 31;
our ($answer, $output);

my ($xd, $svk) = build_test();
my ($copath, $corpath) = get_copath ('i18n');

my $tree = create_basic_tree ($xd, '//');

$svk->checkout ('//A', $copath);

append_file ("$copath/Q/qu", "some changes\n");

my $msg = "\x{ab}\x{eb}"; # Chinese hate in big5
my $msgutf8 = '恨';

set_editor(<< "TMP");
\$_ = shift;
open _ or die \$!;
\@_ = ("I $msg software\n", <_>);
close _;
unlink \$_;
open _, '>', \$_ or die \$!;
print _ \@_;
close _;
TMP
is_output ($svk, 'cp', [-m => $msg, '--encoding', 'big5', '//A' => '//A-cp'],
	   ['Committed revision 3.']);

is_output ($svk, 'commit', [$copath],
	   ['Waiting for editor...',
	    "Can't decode commit message as utf8, try --encoding."]);
is_output ($svk, 'commit', [$copath, '--encoding', 'big5'],
	   ['Waiting for editor...',
	    'Committed revision 4.']);
is_output_like ($svk, 'log', [-r4 => $copath],
		qr/\Q$msgutf8\E/);

is_output ($svk, 'mkdir', [-m => $msg, '--encoding', 'big5', "//A/$msgutf8-dir"],
	   ["Can't decode path as big5-eten, try --encoding."]);
is_output ($svk, 'mkdir', [-m => $msg, '--encoding', 'big5', "//A/$msg-dir"],
	   ['Committed revision 5.']);
$svk->up ($copath);
ok (-e "$copath/$msgutf8-dir");
overwrite_file ("$copath/$msgutf8-dir/newfile", "new file\n");
overwrite_file ("$copath/$msgutf8-dir/newfile2", "new file\n");
overwrite_file ("$copath/$msgutf8-dir/$msg", "new file\n");
is_output ($svk, 'add', ["$copath/$msgutf8-dir/$msg"],
	   [__"Unknown target: $msg."]);
is_output ($svk, 'add', ["$copath/$msgutf8-dir/newfile2"],
	   [__"A   $copath/$msgutf8-dir/newfile2"]);
is_output ($svk, 'st', [$copath],
	   [__"?   $copath/$msgutf8-dir/newfile",
	    __"A   $copath/$msgutf8-dir/newfile2"]);
is_output ($svk, 'ls', ["//A/$msgutf8-dir"],
	   []);
is_output ($svk, 'ls', ["//A"],
	   ['Q/', 'be', "$msgutf8-dir/"]);
is_output ($svk, 'ls', ["//A/$msg-dir"],
	   ["Can't decode path as utf8, try --encoding."]);
#### BEGIN big5 enivonrment
setlocale (LC_CTYPE, $ENV{LC_CTYPE} = 'zh_TW.Big5');
is_output_like ($svk, 'log', [-r4 => '//'],
		qr/\Q$msg\E/);
is_output_like ($svk, 'log', [-vr5 => '//'],
		qr/\Q$msg-dir\E/);

rmtree [$copath];
is_output ($svk, 'checkout', ['//A', $copath],
	   ["Syncing //A(/A) in $corpath to 5.",
	    __"A   $copath/Q",
	    __"A   $copath/Q/qu",
	    __"A   $copath/Q/qz",
	    __"A   $copath/be",
	    __"A   $copath/$msg-dir"], 'checkout reports files in native encoding');

ok (-e "$copath/$msg-dir", 'file checked out in filename of native encoding');
ok (!-e "$copath/$msgutf8-dir", 'not utf8');

overwrite_file ("$copath/$msg-dir/$msg", "with big5 filename\n");
is_output ($svk, 'st', [$copath],
	   [__"?   $copath/$msg-dir/$msg"]);
is_output ($svk, 'st', ["$copath/$msg-dir"],
	   [__"?   $copath/$msg-dir/$msg"]);
is_output ($svk, 'add', ["$copath/$msg-dir/$msg"],
	   [__"A   $copath/$msg-dir/$msg"]);

is_output ($svk, 'commit', ["$copath/$msg-dir"],
	   ['Waiting for editor...',
	    'Committed revision 6.']);
is_output ($svk, 'st', [$copath],
	   [], 'clean checkout after commit');
is_output ($svk, 'st', ["$copath/$msg-dir"],
	   [], 'clean checkout after commit');
is_output ($svk, 'rm', ["$copath/$msg-dir/$msg"],
	   [__"D   $copath/$msg-dir/$msg"]);
is_output ($svk, 'commit', ["$copath/$msg-dir"],
	   ['Waiting for editor...',
	    'Committed revision 7.']);
is_output ($svk, 'st', ["$copath/$msg-dir"],
	   [], 'clean checkout after commit');
is_output ($svk, 'ls', ["//A/$msgutf8-dir"],
	   ["Can't decode path as big5-eten, try --encoding."]);
is_output ($svk, 'ls', ["//A"],
	   ['Q/', 'be', "$msg-dir/"]);
is_output ($svk, 'ls', ["//A/$msg-dir"],
	   []);

#### BEGIN latin-1 enivonrment
setlocale (LC_CTYPE, $ENV{LC_CTYPE} = 'en_US.ISO8859-1');
rmtree [$copath];
TODO: {
local $TODO = 'gracefully handle characters not in this locale';
is_output ($svk, 'checkout', ['//A', $copath],
	   ["Syncing //A(/A) in $corpath to 7.",
	    __"A   $copath/Q",
	    __"A   $copath/Q/qu",
	    __"A   $copath/Q/qz",
	    __"A   $copath/be",
	    __"    $copath/?-dir - skipped"],
	   'gracefully handle characters not in this locale');
}

# reset
setlocale (LC_CTYPE, $ENV{LC_CTYPE} = 'en_US.UTF-8');