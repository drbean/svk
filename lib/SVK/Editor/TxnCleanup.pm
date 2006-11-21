# BEGIN BPS TAGGED BLOCK {{{
# COPYRIGHT:
# 
# This software is Copyright (c) 2003-2006 Best Practical Solutions, LLC
#                                          <clkao@bestpractical.com>
# 
# (Except where explicitly superseded by other copyright notices)
# 
# 
# LICENSE:
# 
# 
# This program is free software; you can redistribute it and/or
# modify it under the terms of either:
# 
#   a) Version 2 of the GNU General Public License.  You should have
#      received a copy of the GNU General Public License along with this
#      program.  If not, write to the Free Software Foundation, Inc., 51
#      Franklin Street, Fifth Floor, Boston, MA 02110-1301 or visit
#      their web page on the internet at
#      http://www.gnu.org/copyleft/gpl.html.
# 
#   b) Version 1 of Perl's "Artistic License".  You should have received
#      a copy of the Artistic License with this package, in the file
#      named "ARTISTIC".  The license is also available at
#      http://opensource.org/licenses/artistic-license.php.
# 
# This work is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
# 
# CONTRIBUTION SUBMISSION POLICY:
# 
# (The following paragraph is not intended to limit the rights granted
# to you to modify and distribute this software under the terms of the
# GNU General Public License and is only of importance to you if you
# choose to contribute your changes and enhancements to the community
# by submitting them to Best Practical Solutions, LLC.)
# 
# By intentionally submitting any modifications, corrections or
# derivatives to this work, or any other work intended for use with
# Request Tracker, to Best Practical Solutions, LLC, you confirm that
# you are the copyright holder for those contributions and you grant
# Best Practical Solutions, LLC a nonexclusive, worldwide,
# irrevocable, royalty-free, perpetual, license to use, copy, create
# derivative works based on those contributions, and sublicense and
# distribute those contributions and any derivatives thereof.
# 
# END BPS TAGGED BLOCK }}}
package SVK::Editor::TxnCleanup;
use strict;
use SVK::Version;  our $VERSION = $SVK::VERSION;

require SVN::Delta;
use base 'SVK::Editor::ByPass';


=head1 NAME

SVK::Editor::TxnCleanup - An editor that aborts a txn when it is aborted

=head1 SYNOPSIS

 my $editor = ...
 # stack the txn cleanup editor on
 $editor = SVK::Editor::TxnCleanup-> (_editor => [$editor], txn => $txn );
 # ... do some stuff ...
 $editor->abort_edit;
 # $txn->abort gets called.

=cut

sub abort_edit {
    my $self = shift;
    my $ret = $self->SUPER::abort_edit(@_);
    $self->{txn}->abort;
    delete $self->{txn};
    return $ret;
}


1;
