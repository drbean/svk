#!/usr/bin/perl -w

use strict;

use Test::More tests => 11;
use File::Path;
use Cwd;
use SVK::Test;

my ($xd, $svk) = build_test();
our $output;
my ($copath, $corpath) = get_copath ('smerge');
my (undef, undef, $repos) = $xd->find_repos ('//', 1);
my $uuid = $repos->fs->get_uuid;

$svk->mkdir ('-m', 'trunk', '//trunk');
my $tree = create_basic_tree ($xd, '//trunk');
is_output($svk, 'ls', ['//trunk/'],
    [
        'A/',
        'B/',
        'C/',
        'D/',
        'me',
    ]
);
is_output($svk, 'ls', ['//trunk/A'],
    [
        'Q/',
        'be',
    ]
);
is_output($svk, 'ls', ['-R', '//trunk/'],
    [
        'A/',
        ' Q/',
        '  qu',
        '  qz',
        ' be',
        'B/',
        ' S/',
        '  P/',
        '   pe',
        '  Q/',
        '   qu',
        '   qz',
        '  be',
        ' fe',
        'C/',
        ' R/',
        'D/',
        ' de',
        'me',
    ]
);

is_output($svk, 'ls', ['-R', '-r', '3', '//trunk/A'],
    [
        'Q/',
        ' qu',
        ' qz',
        'be',
    ]
);

is_output($svk, 'rm', ['-m', 'remove //trunk/A', '//trunk/A'],
    [
        'Committed revision 4.',
    ]
);

is_output($svk, 'ls', ['//trunk/'],
    [
        'B/',
        'C/',
        'D/',
        'me',
    ]
);
is_output($svk, 'ls', ['-R', '//trunk/'],
    [
        'B/',
        ' S/',
        '  P/',
        '   pe',
        '  Q/',
        '   qu',
        '   qz',
        '  be',
        ' fe',
        'C/',
        ' R/',
        'D/',
        ' de',
        'me',
    ]
);

is_output($svk, 'ls', ['-r', '3', '//trunk/'],
    [
        'A/',
        'B/',
        'C/',
        'D/',
        'me',
    ]
);

is_output($svk, 'ls', ['-r', '3', '//trunk/A'],
    [
        'Q/',
        'be',
    ]
);

is_output($svk, 'ls', ['-R', '-r', '3', '//trunk/'],
    [
        'A/',
        ' Q/',
        '  qu',
        '  qz',
        ' be',
        'B/',
        ' S/',
        '  P/',
        '   pe',
        '  Q/',
        '   qu',
        '   qz',
        '  be',
        ' fe',
        'C/',
        ' R/',
        'D/',
        ' de',
        'me',
    ]
);

is_output($svk, 'ls', ['-R', '-r', '3', '//trunk/A'],
    [
        'Q/',
        ' qu',
        ' qz',
        'be',
    ]
);

