package SVN::XD;
use strict;
require SVN::Core;
require SVN::Repos;
require SVN::Fs;
require SVN::Delta;
use Data::Hierarchy;
use File::Spec;
use YAML;

our $VERSION = '0.01';

sub new {
    my $class = shift;
    my $self = bless {}, $class;
    %$self = @_;
    return $self;
}


sub do_update {
    my ($info, %arg) = @_;
    my $fs = $arg{repos}->fs;

    warn "syncing $arg{depotpath}($arg{path}) to $arg{copath} from $arg{startrev} to $arg{rev}";
    my (undef,$anchor,$target) = File::Spec->splitpath ($arg{path});
    my (undef,undef,$copath) = File::Spec->splitpath ($arg{copath});
    chop $anchor;
    SVN::Repos::dir_delta ($fs->revision_root ($arg{startrev}), $anchor, $target,
			   $fs->revision_root ($arg{rev}), $arg{path},
			   SVN::XD::UpdateEditor->new (_debug => 0,
						       target => $target,
						       copath => $copath,
						      ),
#			   SVN::Delta::Editor->new(_debug=>1),
			   1, 1, 0, 1);
}

use File::Find;

sub checkout_crawler {
    my ($info, %arg) = @_;

    find(sub {
	     my $cpath = $File::Find::name;
	     return if -d $cpath;
	     $cpath =~ s|^$arg{copath}/|$arg{path}/|;

	     my $kind = $arg{root}->check_path ($cpath);
	     if ($kind == $SVN::Node::none) {
		 &{$arg{cb_unknown}} ($cpath, $File::Find::name);
		 return;
	     }

	     &{$arg{cb_changed}} ($cpath, $File::Find::name)
		 if md5file($File::Find::name) ne
		     $arg{root}->file_md5_checksum ($cpath);
	  }, $arg{copath});

}

sub md5file {
    my $fname = shift;
    open my $fh, '<', $fname;
    my $ctx = Digest::MD5->new;
    $ctx->addfile($fh);
    return $ctx->hexdigest;
}


package SVN::XD::UpdateEditor;
require SVN::Delta;
our @ISA = qw(SVN::Delta::Editor);
use File::Path;
use Digest::MD5;

sub md5 {
    my $fh = shift;
    my $ctx = Digest::MD5->new;
    $ctx->addfile($fh);
    return $ctx->hexdigest;
}

sub open_root {
    my ($self, $baserev) = @_;
    $self->{baserev} = $baserev;
    return '';
}

sub add_file {
    my ($self, $path) = @_;
    $path =~ s|^$self->{target}/|$self->{copath}/|;
    $self->{info}{$path}{status} = (-e $path ? undef : ['A']);
    return $path;
}

sub open_file {
    my ($self, $path) = @_;
    $path =~ s|^$self->{target}/|$self->{copath}/|;
    $self->{info}{$path}{status} = (-e $path ? [] : undef);
    return $path;
}

sub apply_textdelta {
    my ($self, $path, $checksum) = @_;
    return unless $self->{info}{$path}{status};
    my ($fh, $base);
    unless ($self->{info}{$path}{status}[0]) {
	my (undef,$dir,$file) = File::Spec->splitpath ($path);
	open $base, '<', $path;

	if ($checksum) {
	    my $md5 = md5($base);
	    if ($checksum ne $md5) {
		warn "base checksum mismatch for $path, should do merge";
		warn "$checksum vs $md5\n";
		close $base;
		undef $self->{info}{$path}{status};
		return undef;
#		$self->{info}{$path}{status}[0] = 'G';
	    }
	    seek $base, 0, 0;
	}
	$self->{info}{$path}{status}[0] = 'U';

	my $basename = "$dir.svk.$file.base";
	rename ($path, $basename);
	$self->{info}{$path}{base} = [$base, $basename];

    }
    open $fh, '>', $path or warn "can't open $path";
    $self->{info}{$path}{fh} = $fh;
    return [SVN::TxDelta::apply ($base || SVN::Core::stream_empty(),
				 $fh, undef, undef)];
}

sub close_file {
    my ($self, $path, $checksum) = @_;
    my $info = $self->{info}{$path};
    no warnings 'uninitialized';
    # let close_directory reports about its children
    if ($info->{status}) {
	print sprintf ("%1s%1s \%s\n",$info->{status}[0],
		       $info->{status}[1], $path);
    }
    else {
	print "   $path - skipped\n";
    }
    if ($info->{base}) {
	close $info->{base}[0];
	unlink $info->{base}[1];
    }
    close $info->{fh};
    undef $self->{info}{$path};
}

sub add_directory {
    my ($self, $path) = @_;
    $path = $self->{copath} if $path eq $self->{copath};
    $path =~ s|^$self->{target}/|$self->{copath}/|;
    mkdir ($path);
    return $path;
}

sub open_directory {
    my ($self, $path) = @_;
    $path = $self->{copath} if $path eq $self->{copath};
    $path =~ s|^$self->{target}/|$self->{copath}/|;
    return $path;
}

sub close_directory {
    my ($self, $path) = @_;
    print ".  $path\n";
}


sub delete_entry {
    my ($self, $path, $revision) = @_;
    $path = "$self->{copath}/$path";
    # check if everyone under $path is sane for delete";
    rmtree ([$path]);
    $self->{info}{$path}{status} = ['D'];
}

sub close_edit {
    my ($self) = @_;
    print "finishing update\n";
}


1;
