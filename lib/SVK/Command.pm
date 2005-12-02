package SVK::Command;
use strict;
use base qw(App::CLI App::CLI::Command);
use SVK::Version;  our $VERSION = $SVK::VERSION;
use Getopt::Long qw(:config no_ignore_case bundling);

use SVK::Util qw( get_prompt abs2rel abs_path is_uri catdir bsd_glob from_native
		  find_svm_source $SEP IS_WIN32 HAS_SVN_MIRROR catdepot traverse_history);
use SVK::I18N;
use Encode;
use constant subcommands => '*';

=head1 NAME

SVK::Command - Base class and dispatcher for SVK commands

=head1 SYNOPSIS

    use SVK::Command;
    my $xd = SVK::XD->new ( ... );
    my $cmd = 'checkout';
    my @args = qw( file1 file2 );
    open my $output_fh, '>', 'svk.log' or die $!;
    SVK::Command->invoke ($xd, $cmd, $output_fh, @args);

=head1 DESCRIPTION

This module resolves alias for commands and dispatches them, usually with
the C<invoke> method.  If the command invocation is incorrect, usage
information is displayed instead.

=head1 METHODS

=head2 Class Methods

=cut

use constant alias =>
            qw( ann		annotate
                blame		annotate
                praise		annotate
		co		checkout
		cm		cmerge
		ci		commit
		cp		copy
		del		delete
		remove		delete
		rm		delete
		depot		depotmap
		desc		describe
		di		diff
                h               help
                ?               help
		ls		list
		mi		mirror
		mv		move
		ren		move
		rename	    	move
		pd		propdel
		pdel		propdel
		pe		propedit
		pedit		propedit
		pg		propget
		pget		propget
		pl		proplist
		plist		proplist
		ps		propset
		pset		propset
		sm		smerge
		st		status
		stat		status
		sw		switch
		sy		sync
		up		update
		ver		version
	    );

use constant global_options => ( 'h|help|?'   => 'help',
				 'encoding=s' => 'encoding',
				 'ignore=s@'  => 'ignore',
			       );

my %alias = alias;
my %cmd2alias = map { $_ => [] } values %alias;
while( my($alias, $cmd) = each %alias ) {
    push @{$cmd2alias{$cmd}}, $alias;
}

=head3 invoke ($xd, $cmd, $output_fh, @args)

Takes a L<SVK::XD> object, the command name, the output scalar reference,
and the arguments for the command. The command name is translated with the
C<%alias> map.

On Win32, after C<@args> is parsed for named options, the remaining positional
arguments are expanded for shell globbing with C<bsd_glob>.

=cut

sub invoke {
    my ($pkg, $xd, $cmd, $output, @args) = @_;
    my ($help, $ofh, $ret);
    my $pool = SVN::Pool->new_default;

    local *ARGV = [$cmd, @args];
    $ofh = select $output if $output;
    $ret = eval {$pkg->dispatch ($xd ? (xd => $xd, svnconfig => $xd->{svnconfig}) : (),
				 output => $output) };

    $ofh = select STDERR unless $output;
    print $ret if $ret && $ret !~ /^\d+$/;
    unless (ref($@)) {
	if ($SVN::Core::VERSION gt '1.2.2') {
	    print $@ if $@;
	}
	else {
	    # if an error handler terminates editor call, there will be stack trace
	    print $@ if $@ && $@ !~ m/\n.+\n.+\n/
	}
    }
    $ret = 1 if ($ret ? $ret !~ /^\d+$/ : $@);

    undef $pool;
    select $ofh if $ofh;
    return ($ret || 0);
}

sub run_command {
    my ($self, @args) = @_;
    my $ret;

    local $SVN::Error::handler = sub {
	my $error = $_[0];
	my $error_message = $error->expanded_message();
	$error->clear();
	if ($self->handle_error ($error)) {
	    die \'error handled';
        }
	die $error_message."\n";
    };

    # XXX: this eval is too nasty
    eval {
	# Fake shell globbing on Win32 if we are called from main
	if (IS_WIN32 and caller(1) eq 'main') {
	    @args = map {
		/[?*{}\[\]]/
		    ? bsd_glob($_, File::Glob::GLOB_NOCHECK())
			: $_
		    } @args;
	}
	# XXX: xd needs to know encoding and ignore too
	$self->{xd}{encoding} = $self->{encoding}
	    if $self->{xd};
	$self->{xd}{ignore} = $self->{ignore}
	    if $self->{ignore};
	if ($self->{help} || !(@args = $self->parse_arg(@args))) {
	    select STDERR unless $self->{output};
	    $self->usage;
	}
	else {
	    $self->msg_handler ($SVN::Error::FS_NO_SUCH_REVISION);
	    eval { $self->lock (@args);
		   $self->{xd}->giant_unlock if $self->{xd} && !$self->{hold_giant};
		   $ret = $self->run (@args) };
	    $self->{xd}->unlock if $self->{xd};
	    die $@ if $@;
	}

    };
    # in case parse_arg dies, unlock giant
    $self->{xd}->giant_unlock if $self->{xd} && ref ($self) && !$self->{hold_giant};
    die $@ if $@;
    return $ret;
}

sub error_cmd {
    loc ("Command not recognized, try %1 help.\n", $0);
}

=head3 getopt ($argv, %opt)

Takes a arrayref of argv for run getopt for the command, with
additional %opt getopt options.

=cut

use constant opt_recursive => undef;

sub getopt {
    my ($self, $argv, %opt) = @_;
    local *ARGV = $argv;
    my $recursive = $self->opt_recursive;
    my $toggle = 0;
    $opt{$recursive ? 'N|non-recursive' : 'R|recursive'} = \$toggle
	if defined $recursive;
    die loc ("Unknown options.\n")
	unless GetOptions (%opt, $self->_opt_map ($self->options));
    $self->{recursive} = ($recursive + $toggle) % 2
	if defined $recursive;
}

sub command_options {
    my $self = shift;
    $self->{recursive} = $self->opt_recursive;
    my %opt;
    $opt{$self->{recursive} ? 'N|non-recursive' : 'R|recursive'} =
	sub { $self->{recursive} = !$self->{recursive} }
	    if defined $self->{recursive};
    ($self->options, %opt);
}

=head2 Instance Methods

C<SVK::Command-E<gt>invoke> loads the corresponding class
C<SVK::Command::I<$name>>, so that's the class you want to implement
the following methods in:

=head3 options ()

Returns a hash where the keys are L<Getopt::Long> specs and the values
are a string that will be the keys storing the parsed option in
C<$self>.

Subclasses should override this to add their own options.  Defaults to
an empty list.

=head3 opt_recursive

Defines if the command needs the recursive flag and its default.  The
value will be stored in C<recursive>.

=cut

=head3 parse_arg (@args)

This method is called with the remaining arguments after parsing named
options with C<options> above.  It should use the C<arg_*> methods to
return a list of parsed arguments for the command's C<lock> and C<run> method
to process.  Defaults to return a single C<undef>.

=cut

sub parse_arg { return (undef) }

=head3 lock (@parse_args)

Calls the C<lock_*> methods to lock the L<SVK::XD> object. The arguments
will be what is returned from C<parse_arg>.

=cut

sub lock {
}

=head3 run (@parsed_args)

Actually process the command. The arguments will be what is returned
from C<parse_arg>.

Returned undef on success. Return a string message to notify the
caller errors.

=cut

sub run {
    require Carp;
    Carp::croak("Subclasses should implement its 'run' method!");
}

=head2 Utility Methods

Except for C<arg_depotname>, all C<arg_*> methods below returns a
L<SVK::Path> object, which consists of a hash with the following keys:

=over

=item cinfo

=item copath

=item depotpath

=item path

=item repos

=item repospath

=item report

=item targets

=back

The hashes are handy to pass to many other functions.

=head3 arg_condensed (@args)

Argument is a number of checkout paths.

=cut

sub arg_condensed {
    my $self = shift;
    my @args = map { $self->arg_copath($_) } @_;
    if ($self->{recursive}) {
	# remove redundant targets when doing recurisve
	# if have '' in targets then it means everything
	my @newtarget = @args;
	for my $anchor (sort {length $a->copath <=> length $b->copath} @args) {
	    local $SIG{__WARN__} = sub {};# path::class bug on /foo/bar vs /foo
	    @newtarget = grep {
		$anchor->copath eq $_->copath ||
		!Path::Class::dir($anchor->copath)->subsumes($_->copath) } @newtarget;
	}
	@args = @newtarget;
    }
    return $self->{xd}->target_condensed(@args);
}

=head3 arg_uri_maybe ($arg, $no_new_mirror)

Argument might be a URI or a depotpath.  If it is a URI, try to find it
at or under one of currently mirrored paths.  If not found, prompts the
user to mirror and sync it.

=cut

sub arg_uri_maybe {
    my ($self, $arg, $no_new_mirror) = @_;

    is_uri($arg) or return $self->arg_depotpath($arg);
    HAS_SVN_MIRROR or die loc("cannot load SVN::Mirror");

    $arg =~ s{/?$}{/}; # add a trailing slash at the end

    require URI;
    my $uri = URI->new($arg)->canonical or die loc("%1 is not a valid URI.\n", $arg);
    my $map = $self->{xd}{depotmap};
    foreach my $depot (sort keys %$map) {
        my $repos = eval { ($self->{xd}->find_repos ("/$depot/", 1))[2] } or next;
	foreach my $path ( SVN::Mirror::list_mirror ($repos) ) {
	    my $m = eval {SVN::Mirror->new (
                repos => $repos,
                get_source => 1,
                target_path => $path,
            ) } or next;

            my $rel_uri = $uri->rel(URI->new("$m->{source}/")->canonical) or next;
            next if $rel_uri->eq($uri);
            next if $rel_uri =~ /^\.\./;

            my $depotpath = catdepot($depot, $path, $rel_uri);
            $depotpath = "/$depotpath" if !length($depot);
            return $self->arg_depotpath($depotpath);
	}
    }

    die loc ("URI not allowed here: %1.\n", $no_new_mirror)
	if $no_new_mirror;

    print loc("New URI encountered: %1\n", $uri);

    my $depots = join('|', map quotemeta, sort keys %$map);
    my ($base_uri, $rel_uri);

    {
        my $base = get_prompt(
            loc("Choose a base URI to mirror from (press enter to use the full URI): ", $uri),
            qr/^(?:[A-Za-z][-+.A-Za-z0-9]*:|$)/
        );
        if (!length($base)) {
            $base_uri = $uri;
            $rel_uri = '';
            last;
        }

        $base_uri = URI->new("$base/")->canonical;

        $rel_uri = $uri->rel($base_uri);
        next if $rel_uri->eq($uri);
        next if $rel_uri =~ /^\.\./;
        last;
    }

    my $prompt = loc("
Before svk start mirroring a remote repository, we would like to
explain two terms to you: 'depot path' and 'mirrored path'. A depot
path is like any path in a file system, only that the path is
stored in svk's internal virtual file system.  To avoid confusion,
svk's default depot path begins with //, for example //depot or
//mirror/project.  Now a mirrored path is a depot path with special
properties, which serves as the 'mirror' of a remote repository and
is by convention stored under //mirror/.

Now, you have to assign a name to identify the mirrored repository.
For example, if you name it 'your_project' (without the quotes),
svk will create a mirrored path called //mirror/your_project.
Of course, you can assign a 'full path' for it, for example,
//mymirror/myproject, although this is not really necessary.  If you
just don't care, simply press enter and use svk's default, which is
usually good enough.

");

    my $default = $base_uri->path;
    $default =~ s{^/+|/+$}{}g;
    $default =~ s{(?:/(?=trunk$)|/(?:tags|branche?s)/(?=[^/]+$))}{-};
    $default =~ s{.*/}{};

    my $path = get_prompt(
        $prompt . loc("Depot path: [//mirror/%1] ", $default),
        qr{^(?:$|(?:/(?:$depots)/)?[^/])},
    );
    $path = $default unless length $path;
    $path = "//mirror/$path" unless $path =~ m!^/!;

    my $target = $self->arg_depotpath($path);
    $self->command ('mirror')->run ($target, $base_uri);
  
    # If we're mirroring via svn::mirror, not mirroring the whole history
    # is an option
    my ($m, $answer);
    ($m,undef) = SVN::Mirror::is_mirrored ($target->{'repos'}, 
                                           $target->{'path'}) if (HAS_SVN_MIRROR);
    # If the user is mirroring from svn                                       
    if (UNIVERSAL::isa($m,'SVN::Mirror::Ra'))  {                                
        print loc("
svk needs to mirror the remote repository so you can work locally.
If you're mirroring a single branch, it's safe to use any of the options
below.

If the repository you're mirroring contains multiple branches, svk will
work best if you choose to retrieve all revisions.  Choosing to start
with a recent revision can result in a larger local repository and will
break history-sensitive merging within the mirrored path.

");

        print loc("Synchronizing the mirror for the first time:\n");
        print loc("  a        : Retrieve all revisions (default)\n");
        print loc("  h        : Only the most recent revision\n");
        print loc("  -count   : At most 'count' recent revisions\n");
        print loc("  revision : Start from the specified revision\n");

        $answer = lc(get_prompt(
            loc("a)ll, h)ead, -count, revision? [a] "),
            qr(^[ah]?|^-?\d+$)
            ));
        $answer = 'a' unless length $answer;
    } else { # The user is mirroring with VCP. gotta mirror everything
        $answer = 'a';
    }

    $self->command(
        sync => {
            skip_to => (
                ($answer eq 'a') ? undef :
                ($answer eq 'h') ? 'HEAD-1' :
                ($answer < 0)    ? "HEAD$answer" :
                                $answer
            ),
        }
    )->run ($target);

    my $depotpath = length ($rel_uri) ? $target->{depotpath}."/$rel_uri" : $target->depotpath;
    return $self->arg_depotpath($depotpath);
}

=head3 arg_co_maybe ($arg, $no_new_mirror)

Argument might be a checkout path or a depotpath. If argument is URI then
handles it via C<arg_uri_maybe>.

=cut

sub arg_co_maybe {
    my ($self, $arg, $no_new_mirror) = @_;

    $arg = $self->arg_uri_maybe($arg, $no_new_mirror)->depotpath
	if is_uri($arg);

    my $rev = $arg =~ s/\@(\d+)$// ? $1 : undef;
    my ($repospath, $path, $copath, $cinfo, $repos) =
	$self->{xd}->find_repos_from_co_maybe ($arg, 1);
    from_native ($path, 'path', $self->{encoding});
    my ($view, $revision, $subpath);
    if (($view, $revision, $subpath) = $path =~ m{^/\^(\w+)(?:\@(\d+)(.*))?$}) {
	$revision ||= $repos->fs->youngest_rev;
	($path, $view) = SVK::Command->create_view ($repos, $view, $revision, $subpath);
    }

    my $ret = SVK::Path::Checkout->new
	( repos => $repos,
	  repospath => $repospath,
	  depotpath => $cinfo->{depotpath} || $arg,
	  copath => $copath,
	  report => $copath ? File::Spec->canonpath ($arg) : $arg,
	  path => $path,
	  xd => $self->{xd},
	  view => $view,
	  revision => $rev,
	);
    $ret->as_depotpath unless defined $copath;
    return $ret;
}

=head3 arg_copath ($arg)

Argument is a checkout path.

=cut

sub arg_copath {
    my ($self, $arg) = @_;
    my ($repospath, $path, $copath, $cinfo, $repos) = $self->{xd}->find_repos_from_co ($arg, 1);
    my ($root);
    my ($view, $rev, $subpath);

    if (($view, $rev, $subpath) = $path =~ m{^/\^(\w+)\@(\d+)(.*)$}) {
	($path, $view) = $self->create_view ($repos, $view, $rev, $subpath);
    }

    from_native ($path, 'path', $self->{encoding});
    return SVK::Path::Checkout->new
	( repos => $repos,
	  repospath => $repospath,
	  report => File::Spec->canonpath ($arg),
	  copath => $copath,
	  path => $path,
	  view => $view,
	  cinfo => $cinfo,
	  xd => $self->{xd},
	  depotpath => $cinfo->{depotpath},
	);
}

=head3 arg_depotpath ($arg)

Argument is a depotpath, including the slashes and depot name.

=cut

sub create_view {
    my ($self, $repos, $view, $rev, $subpath) = @_;
    my $fs = $repos->fs;
    $rev = $fs->youngest_rev unless defined $rev;
    require SVK::View;
    my $viewobj = SVK::View->new({name => $view, revision => $rev});
    $viewobj->pool(SVN::Pool->new);
    my $txn = $fs->begin_txn($rev, $viewobj->pool);
    $viewobj->txn($txn);
    $viewobj->root($txn->root($viewobj->pool));
    my $root = $viewobj->root;
    my $content = $root->node_prop ('/', "svk:view:$view");
    my ($anchor, @content) = grep { $_ && !m/^#/ } $content =~ m/^.*$/mg;

    $fs->revision_root ($rev)->dir_entries($anchor); # XXX: for some reasons fsfs needs refresh

    for (@content) {
	my ($del, $path, $target) = m/\s*(-)?(\S+)\s*(\S+)?\s*$/ or die "can't parse $_";
	my $abspath = ($anchor eq '/' ? '/' : "$anchor/").$path;
	if ($del) {
	    die "can't del with target" if $target;
	    $root->delete ($abspath);
	}
	else {
	    # XXX: mkpdir
	    SVN::Fs::copy ($fs->revision_root ($rev), $target,
			   $root, $abspath);
	}
    }
    return (defined $subpath ? $anchor eq '/' ? "/$subpath" : "$anchor/$subpath"
	    : $anchor, $viewobj);
}

sub arg_depotpath {
    my ($self, $arg) = @_;
    my $root;
    my $rev = $arg =~ s/\@(\d+)$// ? $1 : undef;
    my ($repospath, $path, $repos) = $self->{xd}->find_repos ($arg, 1);
    my $view;
    from_native ($path, 'path', $self->{encoding});
    if (($view) = $path =~ m{^/\^(\w+)$}) {
	($path, $view) = $self->create_view($repos, $view, $rev);
    }

    return SVK::Path->new
	( repos => $repos,
	  repospath => $repospath,
	  path => $path,
	  report => $arg,
	  revision => $rev,
	  depotpath => $arg,
	  view => $view,
	);
}

=head3 arg_depotroot ($arg)

Argument is a depot root, or a checkout path that needs to be resolved
into a depot root.

=cut

sub arg_depotroot {
    my ($self, $arg) = @_;

    local $@;
    $arg = eval { $self->arg_co_maybe ($arg || '')->new (path => '/') }
           || $self->arg_depotpath ("//");
    $arg->as_depotpath;

    return $arg;
}

=head3 arg_depotname ($arg)

Argument is a name of depot. such as '' or 'test' that is being used
normally between two slashes.

=cut

sub arg_depotname {
    my ($self, $arg) = @_;

    return $self->{xd}->find_depotname ($arg, 1);
}

=head3 arg_path ($arg)

Argument is a plain path in the filesystem.

=cut

sub arg_path {
    my ($self, $arg) = @_;

    return abs_path ($arg);
}

=head3 parse_revlist ()

Parse -c or -r to a list of [from, to] pairs.

=cut

sub parse_revlist {
    my ($self,$target) = @_;
    die loc("Revision required.\n") unless $self->{revspec} or $self->{chgspec};
    die loc("Can't assign --revision and --change at the same time.\n")
	if $self->{revspec} and $self->{chgspec};
    my ($fromrev, $torev);

    my @revlist = $self->resolve_chgspec($target);
    return @revlist if(@revlist);

    # revspec
    if (($fromrev, $torev) = $self->resolve_revspec($target)) {
	return ([$fromrev, $torev]);
    }
    else {
	die loc ("Revision spec must be N:M.\n");
    }
}

my %empty = map { ($_ => undef) } qw/.schedule .copyfrom .copyfrom_rev .newprop scheduleanchor/;
sub _schedule_empty { %empty };

=head3 lock_target ($target)

XXX Undocumented

=cut

sub lock_target {
    my $self = shift;
    for my $target (@_) {
	$self->{xd}->lock ($target->{copath})
	    if $target->isa('SVK::Path::Checkout');
    }
}

=head3 lock_coroot ($target)

XXX Undocumented

=cut

sub lock_coroot {
    my $self = shift;
    my @tgt = map { $_->copath($_->{copath_target}) }
	grep { $_->isa('SVK::Path::Checkout') } @_;
    return unless @tgt;
    my %roots;
    for (@tgt) {
	my (undef, $coroot) = $self->{xd}{checkout}->get($_);
	$roots{$coroot}++;
    }
    $self->{xd}->lock($_)
	for keys %roots;
}

=head3 brief_usage ($file)

Display an one-line brief usage of the command object.  Optionally, a file
could be given to extract the usage from the POD.

=cut

sub brief_usage {
    my ($self, $file) = @_;
    open my ($podfh), '<', ($file || $self->filename) or return;
    local $/=undef;
    my $buf = <$podfh>;
    if($buf =~ /^=head1\s+NAME\s*SVK::Command::(\w+ - .+)$/m) {
	print "   ",loc(lcfirst($1)),"\n";
    }
    close $podfh;
}

=head3 filename

Return the filename for the command module.

=cut

sub filename {
    my $self = shift;
    my $fname = ref($self);
    $fname =~ s{::[a-z]+}{}; # subcommand
    $fname =~ s{::}{/}g;
    $INC{"$fname.pm"}
}

=head3 usage ($want_detail)

Display usage.  If C<$want_detail> is true, the C<DESCRIPTION>
section is displayed as well.

=cut

sub usage {
    my ($self, $want_detail) = @_;
    my $fname = $self->filename;
    my($cmd) = $fname =~ m{\W(\w+)\.pm$};
    my $parser = Pod::Simple::Text->new;
    my $buf;
    $parser->output_string(\$buf);
    $parser->parse_file($fname);

    $buf =~ s/SVK::Command::(\w+)/\l$1/g;
    $buf =~ s/^AUTHORS.*//sm;
    $buf =~ s/^DESCRIPTION.*//sm unless $want_detail;

    my $aliases = $cmd2alias{lc $cmd} || [];
    if( @$aliases ) {
        $buf .= "ALIASES\n\n";
        $buf .= "     ";
        $buf .= join ', ', sort { $a cmp $b } @$aliases;
    }

    foreach my $line (split(/\n\n+/, $buf, -1)) {
	if (my @lines = $line =~ /^( {4}\s+.+\s*)$/mg) {
            foreach my $chunk (@lines) {
                $chunk =~ /^(\s*)(.+?)( *)(: .+?)?(\s*)$/ or next;
                my $spaces = $3;
                my $loc = $1 . loc($2 . ($4||'')) . $5;
                $loc =~ s/: /$spaces: / if $spaces;
                print $loc, "\n";
            }
            print "\n";
	}
        elsif ($line =~ /^(\s+)(\w+ - .*)$/) {
            print $1, loc($2), "\n\n";
        }
        elsif (length $line) {
            print loc($line), "\n\n";
	}
    }
}

=head2 Error Handling

=cut

# XXX: here we should really just use $SVN::Error::handler.  But the
# problem is that it's called within the contxt of editor calls, so
# returning causes continuation; while dying would cause
# SVN::Delta::Editor to confess.

=head3 handle_error ($error)

XXX Undocumented

=cut

sub handle_error {
    my ($self, $error) = @_;
    my $err_code = $error->apr_err;
    return unless $self->{$err_code};
    $_->($error) for @{$self->{$err_code}};
    return 1;
}

=head3 add_handler ($error, $handler)

XXX Undocumented

=cut

sub add_handler {
    my ($self, $err, $handler) = @_;
    push @{$self->{$err}}, $handler;
}

=head3 msg_handler ($error, $message)

XXX Undocumented

=cut

sub msg_handler {
    my ($self, $err, $msg) = @_;
    $self->add_handler
	($err, sub {
	     print $_[0]->expanded_message."\n".($msg ? "$msg\n" : '');
	 });
}

=head3 msg_handler ($error)

XXX Undocumented

=cut

sub clear_handler {
    my ($self, $err) = @_;
    delete $self->{$err};
}

=head3 command ($cmd, \%args)

Construct a command object of the C<$cmd> subclass and return it.

The new object will share the C<xd> from the calling command object;
contents in C<%args> is also assigned into the new object.

=cut

sub command {
    my ($self, $command, $args, $is_rebless) = @_;

    $command = ucfirst(lc($command));
    require "SVK/Command/$command.pm" unless $command =~ m/::/;

    my $cmd = (
        $is_rebless ? bless($self, "SVK::Command::$command")
                    : "SVK::Command::$command"->new (xd => $self->{xd})
    );
    $cmd->{$_} = $args->{$_} for sort keys %$args;

    return $cmd;
}

=head3 rebless ($cmd, \%args)

Like C<command> above, but modifies the calling object instead
of creating a new one.  Useful for a command object to recast
itself into another command class.

=cut

sub rebless {
    my ($self, $command, $args) = @_;
    return $self->command($command, $args, 1);
}

sub find_checkout_anchor {
    my ($self, $target, $track_merge, $track_sync) = @_;

    my $entry = $self->{xd}{checkout}->get ($target->{copath});
    my $anchor_target = $self->arg_depotpath ($entry->{depotpath});

    return ($anchor_target, undef) unless $track_merge;

    my @rel_path = split(
        '/',
        abs2rel ($target->{path}, $anchor_target->{path}, undef, '/')
    );

    my $copied_from;
    while (!$copied_from) {
        $copied_from = $anchor_target->copied_from ($track_sync);

        if ($copied_from) {
            return ($anchor_target, $copied_from);
        }
        elsif (@rel_path) {
            $anchor_target->descend (shift (@rel_path));
        }
        else {
            return ($self->arg_depotpath ($entry->{depotpath}), undef);
        }
    }
}

sub prompt_depotpath {
    my ($self, $action, $default, $allow_exist) = @_;
    my $path;
    my $prompt = '';
    if (defined $default and $default =~ m{(^/[^/]*/)}) {
        $prompt = loc("
Next, svk will create another depot path, and you have to name it too.
It is usally something like %1your_project/. svk will copy what's in
the mirrored path into the new path.  This depot path is where your
own private branch goes.  You can commit files to it or check out files
from it without affecting the remote repository.  Which means you can
work with version control even when you're offline (yes, this is one
of svk's main features).

Please enter a name for your private branch, and it will be placed
under %1.  If, again, you just don't care, simply press enter and let
svk use the default.

", $1);
	$prompt .= loc("Enter a depot path to %1 into: [%2] ",
		       loc($action), $default
		      );
    }
    else {
	$prompt = loc ("Enter a depot path to %1 into (under // if no leading '/'): ",
		       loc($action));
    }
    while (1) {
	$path = get_prompt($prompt);
	$path = $default if defined $default && !length $path;

	$path =~ s{^//+}{};
	$path =~ s{//+}{/};
	$path = "//$path" unless $path =~ m!^/!;
	$path =~ s{/$}{};

	my $target = $self->arg_depotpath ($path);
	last if $allow_exist or $target->root->check_path ($target->path) == $SVN::Node::none;
	print loc ("Path %1 already exists.\n", $path);
    }

    return $path;
}

## Resolve the correct revision numbers given by "-c"
sub resolve_chgspec {
    my ($self,$target) = @_;
    my @revlist;
    my ($fromrev,$torev);
    if(my $chgspec = $self->{chgspec}) {
	for (split (',', $self->{chgspec})) {
	    my $reverse;
	    if (($fromrev, $torev) = m/^(\d+)-(\d+)$/) {
		--$fromrev;
	    }
	    elsif (($reverse, $torev) = m/^(-?)(\d+)$/) {
		$fromrev = $torev - 1;
		($fromrev, $torev) = ($torev, $fromrev) if $reverse;
	    }
	    else {
		eval { $torev = $self->resolve_revision($target,$_); };
		die loc("Change spec %1 not recognized.\n", $_) if($@);
		$fromrev = $torev - 1;
	    }
	    push @revlist , [$fromrev, $torev];
	}
    }
    return @revlist;
}

sub resolve_revspec {
    my ($self,$target) = @_;
    my $fs = $target->{repos}->fs;
    my $yrev = $fs->youngest_rev;
    my ($r1,$r2);
    if (my $revspec = $self->{revspec}) {
        if ($#{$revspec} > 1) {
            die loc ("Invalid -r.\n");
        } else {
            $revspec = [map {split /:/} @$revspec];
            ($r1, $r2) = map {
                $self->resolve_revision($target,$_);
            } @$revspec;
        }
    }
    return($r1,$r2);
}

sub resolve_revision {
    my ($self,$target,$revstr) = @_;
    return unless defined $revstr;
    my $fs = $target->{repos}->fs;
    my $yrev = $fs->youngest_rev;
    my $rev;
    if($revstr =~ /^HEAD$/i) {
        $rev = $self->find_head_rev($target);
    } elsif ($revstr =~ /^BASE$/i) {
        $rev = $self->find_base_rev($target);
    } elsif ($revstr =~ /\{(\d\d\d\d-\d\d-\d\d)\}/) { 
        my $date = $1; $date =~ s/-//g;
        $rev = $self->find_date_rev($target,$date);
    } elsif (HAS_SVN_MIRROR && (my ($rrev) = $revstr =~ m'^(\d+)@$')) {
	if (my ($m) = SVN::Mirror::is_mirrored ($target->{repos}, $target->{path})) {
	    $rev = $m->find_local_rev ($rrev);
	}
	die loc ("Can't find local revision for %1 on %2.\n", $rrev, $target->path)
	    unless defined $rev;
    } elsif ($revstr =~ /^-\d+$/) {
        $rev = $self->find_head_rev($target) + $revstr;
    } elsif ($revstr =~ /\D/) {
        die loc("%1 is not a number.\n",$revstr)
    } else {
        $rev = $revstr;
    }
    return $rev
}

sub find_date_rev {
    my ($self,$target,$date) = @_;
    # $date should be in yyyymmdd format
    my $fs = $target->{repos}->fs;
    my $yrev = $fs->youngest_rev;

    my ($rev,$last);
    traverse_history (
        root        => $fs->revision_root($yrev),
        path        => $target->path,
        callback    => sub {
            my $props = $fs->revision_proplist($_[1]);
            my $revdate = $props->{'svn:date'};
            $revdate =~ s/T.*$//; $revdate =~ s/-//g;
            if($date > $revdate) {
                $rev = ($last || $_[1]);
                return 0;
            }
            $last = $_[1];
            return 1;
        },
    );
    return $rev || $last;
}


sub find_base_rev {
    my ($self,$target) = @_;
    die(loc("BASE can only be issued with a check-out path\n"))
        unless $target->isa('SVK::Path::Checkout');
    my $rev = $self->{xd}{checkout}->get($target->copath)->{revision};
    return $rev;
}

sub find_head_rev {
    my ($self,$target) = @_;
    $target->as_depotpath;
    my $fs = $target->{repos}->fs;
    my $yrev = $fs->youngest_rev;
    my $rev;
    traverse_history (
        root        => $fs->revision_root($yrev),
        path        => $target->path,
        cross       => 0,
        callback    => sub {
            $rev = $_[1];
            return 0; # only need this once
        },
    );
    return $rev;
}

1;

__DATA__

=head1 SEE ALSO

L<SVK>, L<SVK::XD>, C<SVK::Command::*>

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2005 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
