#!/usr/bin/perl -w
use strict;
use SVK::Test;
plan tests => 5;
our $output;

my ($xd, $svk) = build_test('test');

$svk->mkdir(-m => 'trunk', '/test/trunk');
$svk->mkdir(-m => 'trunk', '/test/branches');
$svk->mkdir(-m => 'trunk', '/test/tags');
my $tree = create_basic_tree($xd, '/test/trunk');

my $depot = $xd->find_depot('test');
my $uri = uri($depot->repospath);

$svk->mirror('//mirror/MyProject', $uri);
$svk->sync('//mirror/MyProject');

my ($copath, $corpath) = get_copath('basic-trunk');

$svk->checkout('//mirror/MyProject/trunk', $copath);

chdir($copath);

is_output_like ($svk, 'branch', ['--create', 'feature/foo', '--switch-to'], qr'Project branch created: feature/foo');

is_output_like ($svk, 'branch', ['--create', 'bugfix/bar', '--switch-to'], qr'Project branch created: bugfix/bar');

$svk->branch('--create', 'bugfix/foobar');
$svk->branch('--create', 'feature/barfoo');

is_output($svk, 'br', ['-l', '//mirror/MyProject'],
          ['bugfix/bar', 'bugfix/foobar', 'feature/barfoo', 'feature/foo']);

$svk->branch('--remove', 'feature/foo', 'feature/barfoo');

is_output($svk, 'br', ['-l', '//mirror/MyProject'],
          ['bugfix/bar', 'bugfix/foobar']);

$svk->branch('--remove', 'bugfix/*');

is_output($svk, 'br', ['-l', '//mirror/MyProject'], []);
