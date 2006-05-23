package SVK::Log::Filter::Head;

use strict;
use warnings;
use SVK::I18N;
use SVK::Log::Filter;

sub setup {
    my ($stash) = $_[STASH];

    my $argument = $stash->{argument};
    die loc("Head: '%1' is not numeric.\n", $argument)
        if $argument !~ /\A \d+\s* \z/xms;

    $stash->{head_remaining} = $argument;
}

sub revision {
    my ($stash) = $_[STASH];
    $stash->{head_remaining}--;

    pipeline('last') if $stash->{head_remaining} < 0;
}

1;

__END__

=head1 SYNOPSIS

SVK::Log::Filter::Head - pass the first N revisions

=head1 DESCRIPTION

The Head filter requires a single integer as its argument.  The integer
represents the number of revisions that the filter should allow to pass down
the filter pipeline.  Head only counts revisions that it sees, so if an
upstream filter causes the pipeline to skip a revision, Head won't (and can't)
count it.  As soon as Head has seen the specified number of revisions, it
stops the pipeline from processing any further revisions.

This filter is particularly useful when searching log messages for patterns
(see L<SVK::Log::Filter::Grep>).  For example, to view the first three
revisions with messages that match "foo", one might use

    svk log --filter "grep foo | head 3"


=head1 STASH/PROPERTY MODIFICATIONS

Head leaves all properties intact and only modifies the stash under the "head_"
namespace.

=head1 AUTHORS

Michael Hendricks E<lt>michael@palmcluster.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2005 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
