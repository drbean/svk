# BEGIN BPS TAGGED BLOCK {{{
# COPYRIGHT:
# 
# This software is Copyright (c) 2007 Best Practical Solutions, LLC
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
# derivatives to this work, or any other work intended for use with SVK,
# to Best Practical Solutions, LLC, you confirm that you are the
# copyright holder for those contributions and you grant Best Practical
# Solutions, LLC a nonexclusive, worldwide, irrevocable, royalty-free,
# perpetual, license to use, copy, create derivative works based on
# those contributions, and sublicense and distribute those contributions
# and any derivatives thereof.
# 
# END BPS TAGGED BLOCK }}}
package SVK::Project;
use strict;
use SVK::Version;  our $VERSION = $SVK::VERSION;
use Path::Class;
use SVK::Logger;
use SVK::I18N;
use base 'Class::Accessor::Fast';

__PACKAGE__->mk_accessors(
    qw(name trunk branch_location tag_location local_root depot));

=head1 NAME

SVK::Project - SVK project class

=head1 SYNOPSIS

 See below

=head1 DESCRIPTION

The class represents a project within svk.

=cut

use List::MoreUtils 'apply';

sub branches {
    my ( $self, $local ) = @_;

    my $fs              = $self->depot->repos->fs;
    my $root            = $fs->revision_root( $fs->youngest_rev );
    my $branch_location = $local ? $self->local_root : $self->branch_location;

    return [ apply {s{^\Q$branch_location\E/}{}}
        @{ $self->_find_branches( $root, $branch_location ) } ];
}

sub tags {
    my $self = shift;
    return [] unless $self->tag_location;

    my $fs              = $self->depot->repos->fs;
    my $root            = $fs->revision_root( $fs->youngest_rev );
    my $tag_location    = $self->tag_location;

    return [ apply {s{^\Q$tag_location\E/}{}}
        @{ $self->_find_branches( $root, $tag_location ) } ];
}

sub _find_branches {
    my ( $self, $root, $path ) = @_;
    my $pool    = SVN::Pool->new_default;
    return [] if $SVN::Node::none == $root->check_path($path);
    my $entries = $root->dir_entries($path);

    my $trunk = SVK::Path->real_new(
        {   depot    => $self->depot,
            revision => $root->revision_root_revision,
            path     => $self->trunk
        }
    );

    my @branches;

    for my $entry ( sort keys %$entries ) {
        next unless $entries->{$entry}->kind == $SVN::Node::dir;
        my $b = $trunk->mclone( path => $path . '/' . $entry );
        next if $b->path eq $trunk->path;

        push @branches, $b->related_to($trunk)
            ? $b->path
            : @{ $self->_find_branches( $root, $path . '/' . $entry ) };
    }
    return \@branches;
}

sub create_from_prop {
    my ($self, $pathobj, $pname) = @_;

    my $fs              = $pathobj->depot->repos->fs;
    my $root            = $fs->revision_root( $fs->youngest_rev );
    my @all_mirrors     = split "\n", $root->node_prop('/','svm:mirror');
    my $prop_path = '/';
    foreach my $m_path (@all_mirrors) {
        if ($pathobj->path =~ m/^$m_path/) {
            $prop_path = $m_path;
            last;
        }
    }
    my $allprops        = $root->node_proplist($prop_path);
    my ($depotroot)     = '/';
    my %projnames = 
        map  { $_ => 1 }
	grep { (1 and !$pname) or ($_ eq $pname)  } # if specified pname, the grep it only
	grep { $_ =~ s/^svk:project:([^:]+):.*$/$1/ }
	grep { $allprops->{$_} =~ /$depotroot/ } sort keys %{$allprops};
    
    # Given a lists of projects: 'rt32', 'rt34', 'rt38' in lexcialorder
    # if the suffix of prop_path matches $project_name like /mirror/rt38 matches rt38
    # then 'rt38' should be used to try before 'rt36', 'rt32'... 
    for my $project_name ( sort { $prop_path =~ m/$b$/ } keys %projnames)  {
	my %props = 
#	    map { $_ => '/'.$allprops->{'svk:project:'.$project_name.':'.$_} }
	    map {
		my $prop = $allprops->{'svk:project:'.$project_name.':'.$_};
		$prop =~ s{/$}{};
		$prop =~ s{^/}{};
		$_ => $prop_path.'/'.$prop }
		('path-trunk', 'path-branches', 'path-tags');
    
	# only the current path matches one of the branches/trunk/tags, the project
	# is returned
	for my $key (keys %props) {
	    return SVK::Project->new(
		{   
		    name            => $project_name,
		    depot           => $pathobj->depot,
		    trunk           => $props{'path-trunk'},
		    branch_location => $props{'path-branches'},
		    tag_location    => $props{'path-tags'},
		    local_root      => "/local/${project_name}",
		}) if $pathobj->path =~ m/^$props{$key}/ or $props{$key} =~ m/^$pathobj->{path}/
		      or $pathobj->path =~ m{^/local/$project_name};
	}
    }
    return undef;
}

sub create_from_path {
    my ($self, $depot, $path) = @_;
    my $rev = undef;

    my $path_obj = SVK::Path->real_new(
        {   depot    => $depot,
            path     => $path
        }
    );
    $path_obj->refresh_revision;

    my ($project_name, $trunk_path, $branch_path, $tag_path) = 
	$self->_find_project_path($path_obj);

    return undef unless $project_name;
    return SVK::Project->new(
	{   
	    name            => $project_name,
	    depot           => $path_obj->depot,
	    trunk           => $trunk_path,
	    branch_location => $branch_path,
	    tag_location    => $tag_path,
	    local_root      => "/local/${project_name}",
	});
}

sub _check_project_path {
    my ($self, $path_obj, $trunk_path, $branch_path, $tag_path) = @_;

    my $checked_result = 1;
    # check trunk, branch, tag, these should be metadata-ed 
    # we check if the structure of mirror is correct, otherwise go again
    for my $_path ($trunk_path, $branch_path, $tag_path) {
        unless ($path_obj->root->check_path($_path) == $SVN::Node::dir) {
            if ($tag_path eq $_path) { # tags directory is optional
                $checked_result = 2; # no tags
            }
            else {
                return 0;
            }
        }
    }
    return $checked_result;
}

# this is heuristics guessing of project and should be replaced
# eventually when we can define project meta data.
sub _find_project_path {
    my ($self, $path_obj) = @_;

    my ($mirror_path,$project_name);
    my ($trunk_path, $branch_path, $tag_path);
    my $current_path = $path_obj->_to_pclass($path_obj->path);
    # Finding inverse layout first
    my ($path) = $current_path =~ m{^/(.+?/(?:trunk|branches|tags)/[^/]+)};
    if ($path) {
        ($mirror_path, $project_name) = # always assume the last entry the projectname
            $path =~ m{^(.*/)?(?:trunk|branches|tags)/(.+)$}; 
        if ($project_name) {
            ($trunk_path, $branch_path, $tag_path) = 
                map { $mirror_path.$_.'/'.$project_name } ('trunk', 'branches', 'tags');
            my $result = $self->_check_project_path ($path_obj, $trunk_path, $branch_path, $tag_path);
	    $tag_path = '' if $result == 2;
            return ($project_name, $trunk_path, $branch_path, $tag_path) if $result > 0;
        }
        $project_name = '';
        $path = '';
    }
    # not found in inverse layout, else 
    ($path) = $current_path =~ m{^(.*?)(?:/(?:trunk|branches/.*?|tags/.*?))?/?$};

    if ($path =~ m{^/local/([^/]+)/?}) { # guess if in local branch
	# should only be 1 entry
	($path) = grep {/\/$1$/} $path_obj->depot->mirror->entries;
	$path =~ s#^/##;
    }

    while (!$project_name) {
	($mirror_path,$project_name) = # always assume the last entry the projectname
	    $path =~ m{^(.*/)?([\w\-_]+)$}; 
	return undef unless $project_name; # can' find any project_name
	$mirror_path ||= '';

	($trunk_path, $branch_path, $tag_path) = 
	    map { $mirror_path.$project_name."/".$_ } ('trunk', 'branches', 'tags');
	my $result = $self->_check_project_path ($path_obj, $trunk_path, $branch_path, $tag_path);
	# if not the last entry, then the mirror_path should contains
	# trunk/branches/tags, otherwise no need to test
	($path) = $mirror_path =~ m{^(.+(?=/(?:trunk|branches|tags)))}
	    unless $result != 0;
	$tag_path = '' if $result == 2;
	$project_name = '' unless $result;
	return undef unless $path;
    }
    return ($project_name, $trunk_path, $branch_path, $tag_path);
}

sub depotpath_in_branch_or_tag {
    my ($self, $name) = @_;
    # return 1 for branch, 2 for tag, others => 0
    return '/'.dir($self->depot->depotname,$self->branch_location,$name)
	if grep { $_ eq $name } @{$self->branches};
    return '/'.dir($self->depot->depotname,$self->tag_location,$name)
	if grep { $_ eq $name } @{$self->tags};
    return ;
}

sub branch_name {
    my ($self, $bpath, $is_local) = @_;
    my $branch_location = $is_local ? $self->local_root : $self->branch_location;
    $bpath =~ s{^\Q$branch_location\E/}{};
    return $bpath;
}

sub branch_path {
    my ($self, $bname, $is_local) = @_;
    my $branch_path = '/'.$self->depot->depotname.'/'.
        ($is_local ?
            $self->local_root."/$bname"
            :
            ($bname ne 'trunk' ?
                $self->branch_location . "/$bname" : $self->trunk)
        );
    return $branch_path;
}

sub info {
    my ($self, $target) = @_;

    $logger->info ( loc("Project name: %1.\n", $self->name));
    if ($target) {
	my $where;
	my $bname;
	if (dir($self->trunk)->subsumes($target->path)) {
	    $where = 'trunk';
	    $bname = 'trunk';
	} elsif (dir($self->branch_location)->subsumes($target->path)) {
	    $where = 'branch';
	    $bname = $target->_to_pclass($target->path)->relative($self->branch_location)->dir_list(0);
	} elsif (dir($self->tag_location)->subsumes($target->path)) {
	    $where = 'tag';
	    $bname = $target->_to_pclass($target->path)->relative($self->tag_location)->dir_list(0);
	}

	if ($where) {
	    $logger->info ( loc("Current Branch: %1 (%2)\n", $bname, $where ));
	    $logger->info ( loc("Depot Path: (%1)\n", $target->depotpath ));
	    if ($where ne 'trunk') { # project trunk should not have Copied info
		for ($target->copy_ancestors) {
		    $logger->info( loc("Copied From: %1, Rev. %2\n", $_->[0], $_->[1]));
		}
	    }
	}
    }
}
1;
