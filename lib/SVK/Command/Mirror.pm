package SVK::Command::Mirror;
use strict;
use SVK::Version;  our $VERSION = $SVK::VERSION;

use base qw( SVK::Command::Commit );
use SVK::I18N;
use SVK::Util qw( is_uri get_prompt traverse_history );

use constant narg => undef;

sub options {
    ('l|list'  => 'list',
     'd|delete|detach'=> 'detach',
     'upgrade' => 'upgrade',
     'relocate'=> 'relocate',
     'unlock'=> 'unlock',
     'recover'=> 'recover');
}

sub lock {} # override commit's locking

sub parse_arg {
    my ($self, @arg) = @_;

    @arg = ('//') if $self->{upgrade} and !@arg;
    return if !@arg;

    my $path = shift(@arg);

    # Allow "svk mi uri://... //depot" to mean "svk mi //depot uri://"
    if (is_uri($path) && $arg[0]) {
        ($arg[0], $path) = ($path, $arg[0]);
    }

    if (defined (my $narg = $self->narg)) {
	return unless $narg == (scalar @arg + 1);
    }

    return ($self->arg_depotpath ($path), @arg);
}

sub run {
    my ( $self, $target, $source, @options ) = @_;

    SVK::Mirror->create(
        {
            depot   => $target->depot,
            path    => $target->path,
            backend => 'SVNRa',
            url     => "$source", # this can be an URI object
            pool    => SVN::Pool->new
        }
    );

    print loc("Mirror initialized.  Run svk sync %1 to start mirroring.\n", $target->report);

    return;
}

package SVK::Command::Mirror::relocate;
use base qw(SVK::Command::Mirror);
use SVK::I18N;

sub run {
    my ($self, $target, $source, @options) = @_;

    # FIXME: add tests and implement
    my $m = $target->is_mirrored;
    $m->relocate($source, @options);

    return;
}

package SVK::Command::Mirror::detach;
use base qw(SVK::Command::Mirror);
use SVK::I18N;

use constant narg => 1;

sub run {
    my ($self, $target) = @_;
    my ($m, $mpath) = $target->is_mirrored;

    die loc("%1 is not a mirrored path.\n", $target->depotpath) if !$m;
    die loc("%1 is inside a mirrored path.\n", $target->depotpath) if $mpath;

    $m->detach(1); # remove svm:source and svm:uuid too
    print loc("Mirror path '%1' detached.\n", $target->depotpath);
    return;
}

package SVK::Command::Mirror::upgrade;
use base qw(SVK::Command::Mirror);
use SVK::I18N;

use constant narg => 1;

sub run {
    my ($self, $target) = @_;
    print loc("nothing to upgrade\n");
    return;
}

package SVK::Command::Mirror::unlock;
use base qw(SVK::Command::Mirror);
use SVK::I18N;

use constant narg => 1;

sub run {
    my ($self, $target) = @_;
    $target->depot->mirror->unlock($target->path_anchor);
    print loc ("mirror locks on %1 removed.\n", $target->report);
    return;
}

package SVK::Command::Mirror::list;
use base qw(SVK::Command::Mirror);
use SVK::I18N;
use List::Util qw( max );

sub parse_arg {
    my ($self, @arg) = @_;
    return (@arg ? @arg : undef);
}

sub run {
    my ( $self, $target ) = @_;

    my @mirror_columns;
    my @depots
        = defined $target
        ? @_[ 1 .. $#_ ]
        : sort keys %{ $self->{xd}{depotmap} }
        ;
    DEPOT:
    foreach my $depot (@depots) {
        $depot =~ s{/}{}g;
        $target = eval { $self->arg_depotpath("/$depot/") };
        if ($@) {
            warn loc( "Depot /%1/ not loadable.\n", $depot );
            next DEPOT;
        }
        my $depot_name = $target->depotname;
        foreach my $path ( $target->depot->mirror->entries ) {
            my $m = $target->depot->mirror->get($path);
            push @mirror_columns, [ "/$depot_name$path", $m->url ];
        }
    }

    my $max_depot_path = max map { length $_->[0] } @mirror_columns;
    my $max_uri        = max map { length $_->[1] } @mirror_columns;

    my $fmt = "%-${max_depot_path}s   %-s\n";
    printf $fmt, loc('Path'), loc('Source');
    print '=' x ( $max_depot_path + $max_uri + 3 ), "\n";

    printf $fmt, @$_ for @mirror_columns;

    return;
}

package SVK::Command::Mirror::recover;
use base qw(SVK::Command::Mirror);
use SVK::Util qw( traverse_history get_prompt );
use SVK::I18N;

use constant narg => 1;

sub run {
    my ($self, $target, $source, @options) = @_;
    die loc("recover not supported.\n");
    my ($m, $mpath) = $target->is_mirrored;

    $self->recover_headrev ($target, $m);
    $self->recover_list_entry ($target, $m);
    return;
}

sub recover_headrev {
    my ($self, $target, $m) = @_;

    my $fs = $target->repos->fs;
    my ($props, $headrev, $rev, $firstrev, $skipped, $uuid, $rrev);

    traverse_history (
        root        => $fs->revision_root ($fs->youngest_rev),
        path        => $m->{target_path},
        cross       => 1,
        callback    => sub {
            $rev = $_[1];
            $firstrev ||= $rev;
            print loc("Analyzing revision %1...\n", $rev),
                  ('-' x 70),"\n",
                  $fs->revision_prop ($rev, 'svn:log'), "\n";

            if ( $headrev = $fs->revision_prop ($rev, 'svm:headrev') ) {
                ($uuid, $rrev) = split(/[:\n]/, $headrev);
                $props = $fs->revision_proplist($rev);
                get_prompt(loc(
                    "Found merge ticket at revision %1 (remote %2); use it? (y/n) ",
                    $rev, $rrev
                ), qr/^[YyNn]/) =~ /^[Nn]/ or return 0; # last
                undef $headrev;
            }
            $skipped++;
            return 1;
        },
    );

    if (!$headrev) {
        die loc("No mirror history found; cannot recover.\n");
    }

    if (!$skipped) {
        print loc("No need to revert; it is already the head revision.\n");
        return;
    }

    get_prompt(
        loc("Revert to revision %1 and discard %*(%2,revision)? (y/n) ", $rev, $skipped),
        qr/^[YyNn]/,
    ) =~ /^[Yy]/ or die loc("Aborted.\n");

    $self->command(
        delete => { direct => 1, message => '' }
    )->run($target);

    $target->refresh_revision;
    $self->command(
        copy => { direct  => 1, message => '' },
    )->run($target->new(revision => $rev) => $target->new);

    # XXX - race condition? should get the last committed rev instead
    $target->refresh_revision;

    $self->command(
        propset => { direct  => 1, revprop => 1 },
    )->run($_ => $props->{$_}, $target) for sort grep {m/^sv[nm]/} keys %$props;

    print loc("Mirror state successfully recovered.\n");
    return;
}

sub recover_list_entry {
    my ($self, $target, $m) = @_;

    my %mirrors = map { ($_ => 1) } SVN::Mirror::list_mirror ($target->repos);

    return if $mirrors{$m->{target_path}}++;

    $self->command ( propset => { direct => 1, message => 'foo' } )->run (
        'svm:mirror' => join ("\n", (grep length, sort keys %mirrors), ''),
        $self->arg_depotpath ('/'.$target->depotname.'/'),
    );

    print loc("%1 added back to the list of mirrored paths.\n", $target->report);
    return;
}

1;

__DATA__

=head1 NAME

SVK::Command::Mirror - Initialize a mirrored depotpath

=head1 SYNOPSIS

 mirror [http|svn]://host/path DEPOTPATH
 mirror cvs::pserver:user@host:/cvsroot:module/... DEPOTPATH
 mirror p4:user@host:1666://path/... DEPOTPATH

 # You may also list the target part first:
 mirror DEPOTPATH [http|svn]://host/path

 mirror --list [DEPOTNAME...]
 mirror --relocate DEPOTPATH [http|svn]://host/path 
 mirror --detach DEPOTPATH
 mirror --recover DEPOTPATH

 mirror --upgrade //
 mirror --upgrade /DEPOTNAME/

=head1 OPTIONS

 -l [--list]            : list mirrored paths
 -d [--detach]          : mark a depotpath as no longer mirrored
 --relocate             : change the upstream URI for the mirrored depotpath
 --recover              : recover the state of a mirror path
 --unlock               : forcibly remove stalled locks on a mirror
 --upgrade              : upgrade mirror state to the latest version

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2005 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
