package SVK::Command::Proplist;
use strict;
our $VERSION = $SVK::VERSION;

use base qw( SVK::Command );
use SVK::XD;
use SVK::I18N;

sub options {
    ('v|verbose' => 'verbose',
     'R|recursive' => 'recursive',
     'r|revision=i' => 'rev',
     'revprop' => 'revprop',
    );
}

sub parse_arg {
    my ($self, @arg) = @_;

    @arg = ('') if $#arg < 0;
    return map { $self->_arg_revprop ($_) } @arg;
}

sub lock { $_[0]->lock_none }

sub run {
    my ($self, @arg) = @_;

    for my $target (@arg) {
        if ($self->{revprop}) {
            my $rev = (defined($self->{rev}) ? $self->{rev} : $target->{revision});
            $self->show_props (
                $target,
                $target->{repos}->fs->revision_proplist($rev),
                $rev,
            );
            next;
        }

	$target->as_depotpath ($self->{rev}) if defined $self->{rev};
        $self->show_props ($target, $self->{xd}->do_proplist ( $target ));
    }

    return;
}

sub show_props {
    my ($self, $target, $props, $rev) = @_;

    %$props or return;

    if ($self->{revprop}) {
        print loc("Unversioned properties on revision %1:\n", $rev);
    }
    else {
        print loc("Properties on %1:\n", $target->{report} || '.');
    }

    for my $key (sort keys %$props) {
        my $value = $props->{$key};
        print $self->{verbose} ? "  $key: $value\n" : "  $key\n";
    }
}

sub _arg_revprop {
    my $self = $_[0];
    goto &{$self->can($self->{revprop} ? 'arg_depotroot' : 'arg_co_maybe')};
}

sub _proplist {
    my ($self, $target) = @_;

    if ($self->{revprop}) {
        return $target->{repos}->fs->revision_proplist(
            (defined($self->{rev}) ? $self->{rev} : $target->{revision})
        )
    }

    if (defined $self->{rev}) {
        $target->as_depotpath ($self->{rev});
    }
    return $self->{xd}->do_proplist ($target);
}


1;

__DATA__

=head1 NAME

SVK::Command::Proplist - List all properties on files or dirs

=head1 SYNOPSIS

 proplist PATH...

=head1 OPTIONS

 -R [--recursive]       : descend recursively
 -v [--verbose]         : print extra information
 -r [--revision] arg    : act on revision ARG instead of the head revision
 --revprop              : operate on a revision property (use with -r)
 --direct               : commit directly even if the path is mirrored

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2004 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
