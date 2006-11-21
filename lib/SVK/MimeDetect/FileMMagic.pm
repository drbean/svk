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
package SVK::MimeDetect::FileMMagic;
use strict;
use warnings;
use base qw( File::MMagic );

use SVK::Util qw( is_binary_file );

=for Workaround:

File::MMagic 1.27 doesn't correctly handle subclassing.  The object returned by
new is blessed into 'File::MMagic' instead of the subclass.  The author has
accepted a patch to correct this behavior.  Once the patched version is
released on CPAN, new() should be removed and the fixed version required.

=cut
sub new {
    my $pkg = shift;
    my $new_self = $pkg->SUPER::new(@_);
    return bless $new_self, $pkg;
}

# override the default implementation because checktype_contents is faster
sub checktype_filename {
    my ($self, $filename) = @_;

    return 'text/plain' if -z $filename;

    # read a chunk and delegate to checktype_contents()
    open my $fh, '<', $filename or die $!;
    binmode($fh);
    read $fh, my $data, 16 * 1024;
    my $type = $self->checktype_contents($data);
    return $type if $type ne 'application/octet-stream';

    # verify File::MMagic's opinion on supposedly binary data
    return $type if is_binary_file($filename);
    return 'text/plain';
}

1;

__END__

=head1 NAME

SVK::MimeDetect::FileMMagic

=head1 DESCRIPTION

Implement MIME type detection using the module File::MMagic.
