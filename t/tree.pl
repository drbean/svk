#!/usr/bin/perl
END {
    rm_test($_) for @TOCLEAN;
}

use strict;
require Data::Hierarchy;
require SVN::Core;
require SVN::Repos;
require SVN::Fs;
use File::Path;
use File::Temp;
use SVK::Util qw( dirname catdir tmpdir can_run abs_path $SEP $EOL IS_WIN32 );
use Test::More;

# Fake standard input
our $answer = 's'; # skip
BEGIN {
    no warnings 'redefine';
    *SVK::Util::get_prompt = sub {
        ref($answer) ? shift(@$answer) : $answer
    } unless $ENV{DEBUG_INTERACTIVE};

    chdir catdir( dirname(__FILE__), '..' );
}

sub plan_svm {
    eval { require SVN::Mirror; 1 } or do {
	plan skip_all => "SVN::Mirror not installed";
	exit;
    };
    plan @_;
}

use Carp;
use SVK;
use SVK::XD;

our @TOCLEAN;
END {
    $SIG{__WARN__} = sub { 1 };
    cleanup_test($_) for @TOCLEAN;
}

our $output = '';
our $copath;

for (qw/SVKRESOLVE SVKMERGE SVKDIFF LC_CTYPE LC_ALL LANG LC_MESSAGES/) {
    $ENV{$_} = '' if $ENV{$_};
}
$ENV{LANGUAGE} = $ENV{LANGUAGES} = 'i-default';

$ENV{HOME} ||= (
    $ENV{HOMEDRIVE} ? catdir(@ENV{qw( HOMEDRIVE HOMEPATH )}) : ''
) || (getpwuid($<))[7];
$ENV{USER} ||= (
    (defined &Win32::LoginName) ? Win32::LoginName() : ''
) || $ENV{USERNAME} || (getpwuid($<))[0];

# Make "prove -l" happy; abs_path() returns "undef" if the path 
# does not exist. This makes perl very unhappy.
@INC = grep defined, map abs_path($_), @INC;

if ($ENV{DEBUG}) {
    {
        package Tie::StdScalar::Tee;
        require Tie::Scalar;
        our @ISA = 'Tie::StdScalar';
        sub STORE { print STDOUT $_[1] ; ${$_[0]} = $_[1]; }
    }
    tie $output => 'Tie::StdScalar::Tee';
}

my $pool = SVN::Pool->new_default;

sub new_repos {
    my $repospath = catdir(tmpdir(), "svk-$$");
    my $reposbase = $repospath;
    my $repos;
    my $i = 0;
    while (-e $repospath) {
	$repospath = $reposbase . '-'. (++$i);
    }
    my $pool = SVN::Pool->new_default;
    $ENV{SVNFSTYPE} ||= (($SVN::Core::VERSION =~ /^1\.0/) ? 'bdb' : 'fsfs');
    $repos = SVN::Repos::create("$repospath", undef, undef, undef,
				{'fs-type' => $ENV{SVNFSTYPE}})
	or die "failed to create repository at $repospath";
    return $repospath;
}

sub build_test {
    my (@depot) = @_;

    my $depotmap = {map {$_ => (new_repos())[0]} '',@depot};
    my $xd = SVK::XD->new (depotmap => $depotmap,
			   svkpath => $depotmap->{''});
    my $svk = SVK->new (xd => $xd, $ENV{DEBUG_INTERACTIVE} ? () : (output => \$output));
    push @TOCLEAN, [$xd, $svk];
    return ($xd, $svk);
}

sub get_copath {
    my ($name) = @_;
    my $copath = SVK::Target->copath ('t', "checkout/$name");
    mkpath [$copath] unless -d $copath;
    rmtree [$copath] if -e $copath;
    return ($copath, File::Spec->rel2abs($copath));
}

sub rm_test {
    my ($xd, $svk) = @{+shift};
    for my $depot (sort keys %{$xd->{depotmap}}) {
	my $path = $xd->{depotmap}{$depot};
	die if $path eq '/';
	rmtree [$path];
    }
}

sub cleanup_test {
    return unless $ENV{TEST_VERBOSE};
    my ($xd, $svk) = @{+shift};
    use YAML;
    print Dump($xd);
    for my $depot (sort keys %{$xd->{depotmap}}) {
	my (undef, undef, $repos) = $xd->find_repos ("/$depot/", 1);
	print "===> depot $depot (".$repos->fs->get_uuid."):\n";
	$svk->log ('-v', "/$depot/");
	print ${$svk->{output}};
    }
}

sub append_file {
    my ($file, $content) = @_;
    open my ($fh), '>>', $file or die "can't append $file: $!";
    print $fh $content;
    close $fh;
}

sub overwrite_file {
    my ($file, $content) = @_;
    open my ($fh), '>', $file or confess "Cannot overwrite $file: $!";
    print $fh $content;
    close $fh;
}

sub overwrite_file_raw {
    my ($file, $content) = @_;
    open my ($fh), '>:raw', $file or confess "Cannot overwrite $file: $!";
    print $fh $content;
    close $fh;
}

sub is_file_content {
    my ($file, $content, $test) = @_;
    open my ($fh), '<', $file or confess "Cannot read from $file: $!";
    local $/;
    @_ = (<$fh>, $content, $test);
    goto &is;
}

sub is_file_content_raw {
    my ($file, $content, $test) = @_;
    open my ($fh), '<:raw', $file or confess "Cannot read from $file: $!";
    local $/;
    @_ = (<$fh>, $content, $test);
    goto &is;
}

sub is_output {
    my ($svk, $cmd, $arg, $expected, $test) = @_;
    $svk->$cmd (@$arg);
    my $cmp = (grep {ref ($_) eq 'Regexp'} @$expected)
	? \&is_deeply_like : \&is_deeply;
    @_ = ([split (/\r?\n/, $output)], $expected, $test || join(' ', map { / / ? qq("$_") : $_ } $cmd, @$arg));
    goto &$cmp;
}

sub is_sorted_output {
    my ($svk, $cmd, $arg, $expected, $test) = @_;
    $svk->$cmd (@$arg);
    my $cmp = (grep {ref ($_) eq 'Regexp'} @$expected)
	? \&is_deeply_like : \&is_deeply;
    @_ = ([sort split (/\r?\n/, $output)], [sort @$expected], $test || join(' ', $cmd, @$arg));
    goto &$cmp;
}

sub is_deeply_like {
    my ($got, $expected, $test) = @_;
    for (0..$#{$expected}) {
	if (ref ($expected->[$_]) eq 'SCALAR' ) {
	    @_ = ($#{$got}, $#{$got}, $test);
	    goto &is;
	}
	elsif (ref ($expected->[$_]) eq 'Regexp' ) {
	    unless ($got->[$_] =~ m/$expected->[$_]/) {
		diag "Different at $_:\n$got->[$_]\n$expected->[$_]";
		@_ = (0, $test);
		goto &ok;
	    }
	}
	else {
	    if ($got->[$_] ne $expected->[$_]) {
		diag "Different at $_:\n$got->[$_]\n$expected->[$_]";
		@_ = (0, $test);
		goto &ok;
	    }
	}
    }
    @_ = ($#{$expected}, $#{$got}, $test);
    goto &is;
}

sub is_output_like {
    my ($svk, $cmd, $arg, $expected, $test) = @_;
    $svk->$cmd (@$arg);
    @_ = ($output, $expected, $test || join(' ', $cmd, @$arg));
    goto &like;
}

sub copath {
    SVK::Target->copath ($copath, @_);
}

sub status_native {
    my $copath = shift;
    my @ret;
    while (my ($status, $path) = splice (@_, 0, 2)) {
	push @ret, join (' ', $status, $copath ? copath ($path) :
			 File::Spec->catfile (File::Spec::Unix->splitdir ($path)));
    }
    return @ret;
}

sub status {
    my @ret;
    while (my ($status, $path) = splice (@_, 0, 2)) {
	push @ret, join (' ', $status, $path);
    }
    return @ret;
}

require SVN::Simple::Edit;

sub get_editor {
    my ($repospath, $path, $repos) = @_;

    return SVN::Simple::Edit->new
	(_editor => [SVN::Repos::get_commit_editor($repos,
						   "file://$repospath",
						   $path,
						   'svk', 'test init tree',
						   sub {})],
	 base_path => $path,
	 root => $repos->fs->revision_root ($repos->fs->youngest_rev),
	 missing_handler => SVN::Simple::Edit::check_missing ());
}

sub create_basic_tree {
    my ($xd, $depot) = @_;
    my $pool = SVN::Pool->new_default;
    my ($repospath, $path, $repos) = $xd->find_repos ($depot, 1);

    local $/ = $EOL;
    my $edit = get_editor ($repospath, $path, $repos);
    $edit->open_root ();

    $edit->modify_file ($edit->add_file ('/me'),
			"first line in me$/2nd line in me$/");
    $edit->modify_file ($edit->add_file ('/A/be'),
			"\$Rev\$ \$Revision\$$/\$FileRev\$$/first line in be$/2nd line in be$/");
    $edit->change_file_prop ('/A/be', 'svn:keywords', 'Rev URL Revision FileRev');
    $edit->modify_file ($edit->add_file ('/A/P/pe'),
			"first line in pe$/2nd line in pe$/");
    $edit->add_directory ('/B');
    $edit->add_directory ('/C');
    $edit->add_directory ('/A/Q');
    $edit->change_dir_prop ('/A/Q', 'foo', 'prop on A/Q');
    $edit->modify_file ($edit->add_file ('/A/Q/qu'),
			"first line in qu$/2nd line in qu$/");
    $edit->modify_file ($edit->add_file ('/A/Q/qz'),
			"first line in qz$/2nd line in qz$/");
    $edit->add_directory ('/C/R');
    $edit->close_edit ();
    my $tree = { child => { me => {},
			    A => { child => { be => {},
					      P => { child => {pe => {},
							      }},
					      Q => { child => {qu => {},
							       ez => {},
							      }},
					    }},
			    B => {},
			    C => { child => { R => { child => {}}}}
			  }};
    my $rev = $repos->fs->youngest_rev;
    $edit = get_editor ($repospath, $path, $repos);
    $edit->open_root ();
    $edit->modify_file ('/me', "first line in me$/2nd line in me - mod$/");
    $edit->modify_file ($edit->add_file ('/B/fe'),
			"file fe added later$/");
    $edit->delete_entry ('/A/P');
    $edit->copy_directory('/B/S', "file://${repospath}/${path}/A", $rev);
    $edit->modify_file ($edit->add_file ('/D/de'),
			"file de added later$/");
    $edit->close_edit ();

    $tree->{child}{B}{child}{fe} = {};
    # XXX: have to clone this...
    %{$tree->{child}{B}{child}{S}} = (child => {%{$tree->{child}{A}{child}}},
				      history => '/A:1');
    delete $tree->{child}{A}{child}{P};
    $tree->{child}{D}{child}{de} = {};

    return $tree;
}

sub waste_rev {
    my ($svk, $path) = @_;
    $svk->mkdir('-m', 'create', $path);
    $svk->rm('-m', 'create', $path);
}

sub tree_from_fsroot {
    # generate a hash describing a given fs root
}

sub tree_from_xdroot {
    # generate a hash describing the content in an xdroot
}

sub __ ($) {
    my $path = shift;
    $path =~ s{/}{$SEP}go;
    return $path;
}

sub _x { IS_WIN32 ? 1 : -x $_[0] }
sub not_x { IS_WIN32 ? 1 : not -x $_[0] }
sub _l { IS_WIN32 ? 1 : -l $_[0] }
sub not_l { IS_WIN32 ? 1 : not -l $_[0] }

sub uri {
    my $file = shift;
    $file =~ s{^|\\}{/}g if IS_WIN32;
    return "file://$file";
}

my @unlink;
sub set_editor {
    my $tmp = File::Temp->new( SUFFIX => '.pl', UNLINK => 0 );
    print $tmp $_[0];
    $tmp->close;

    my $perl = can_run($^X);
    my $tmpfile = $tmp->filename;

    if (defined &Win32::GetShortPathName) {
	$perl = Win32::GetShortPathName($perl);
	$tmpfile = Win32::GetShortPathName($tmpfile);
    }

    chmod 0755, $tmpfile;
    push @unlink, $tmpfile;

    $ENV{SVN_EDITOR} = "$perl $tmpfile";
}

sub replace_file {
    my ($file, $from, $to) = @_;
    my @content;

    open my $fh, '<', $file or croak "Cannot open $file: $!";
    while (<$fh>) {
        s/$from/$to/g;
        push @content, $_;
    }
    close $fh;

    open $fh, '>', $file or croak "Cannot open $file: $!";
    print $fh @content;
    close $fh;
}

END {
    unlink $_ for @unlink;
}

1;
