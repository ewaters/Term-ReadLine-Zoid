package Term::ReadLine::Zoid;

use strict;
use vars '$AUTOLOAD';
use Term::ReadLine::Zoid::Base;
no warnings; # undef == '' down here

our @ISA = qw/Term::ReadLine::Zoid::Base Term::ReadLine::Stub/; # explicitly not using T:RL::Stub
our $VERSION = '0.04';

sub import { # terrible hack - Term::ReadLine 5.6.x is defective
	return unless (caller())[0] eq 'Term::ReadLine' and $] < 5.008 ;
	*Term::ReadLine::Stub::new = sub {
		shift;
		my $self = bless {}, 'Term::ReadLine::Zoid';
		return $self->_init(@_);
	};
}

sub new {
	my $self = bless {}, shift(@_);
	return $self->_init(@_);
}

our $_current = undef;

sub _init {
	my ($self, $name, $in, $out) = @_;

	%$self = (
		appname   => $name,
		IN        => $in || *STDIN{IO},
		OUT       => $out || *STDOUT{IO},
		history   => [],
		hist_cnt  => 1,
		default_mode => __PACKAGE__,
		undostack => [],
		key_map   => {},
	%$self );
	$$self{config}{$$_[0]} ||= $$_[1] for
			[ minline        => 0    ],
			[ autohistory    => 1    ],
			[ autoenv        => 1    ],
			[ autolist       => 1    ],
			[ automultiline  => 1    ],
			[ PS2            => '> ' ],
			[ maxcomplete    => 150  ],
			[ ignore_comment => '#'  ];
	$$self{key_map}{command}{_on_switch} = sub {
		return $$self{_loop} = undef if $$self{_vi_mini_b};
		$$self{vi_command}   = '';
		$$self{vi_history} ||= [];
		$self->left unless $_[1] or $$self{pos}[0] == 0;
		return 'Term::ReadLine::Zoid::ViCommand';
	};
	$$self{key_map}{isearch}{_on_switch} = sub {
		$$self{is_lock} = undef;
		$$self{is_save} = [[''], [0,0], undef];
		return 'Term::ReadLine::Zoid::ISearch';
	};
	$$self{key_map}{multiline}{_on_switch} =
		sub { return 'Term::ReadLine::Zoid::MultiLine' };
	$$self{_key_map} = $$self{key_map}; # local backup

#	my $chr_map = $self->{chr_map} || {};
#	$$self{chr_map} = $default_chr_map;
#	$self->bind_chr($_, $$chr_map{$_}) for keys %$chr_map;

	# rcfiles
	my ($rcfile) = grep {-e $_ && -r _} 
		"$ENV{HOME}/.perl_rl_zoid_rc",
		"$ENV{HOME}/.zoid/perl_rl_zoid_rc",
		"/etc/perl_rl_zoid_rc";
	if ($rcfile) {
		local $_current = $self;
		do $rcfile;
	}

	return $self;
}

sub AUTOLOAD {
	$AUTOLOAD =~ s/.*:://;
	return if $AUTOLOAD eq 'DESTROY';
	my $self = shift;
	my $sub = $$self{default_mode}.'::'.$AUTOLOAD;
	$self->$sub(@_);
}

# ############ #
# ReadLine api #
# ############ #

sub ReadLine { return 'Term::ReadLine::Zoid' }

sub readline {
	my ($self, $prompt, $preput) = @_;
	$self->reset();
	$self->switch_mode();
	$$self{prompt} = defined($prompt) ? $prompt : $$self{appname}.' !> ';
	$$self{lines}  = [ split /\n/, $preput ] if defined $preput;
	my $title = $$self{config}{title} || $$self{appname};
	$self->title($title);
	$self->new_line();
	$self->loop();
	return $self->_return();
}

sub _return { # also used by continue
	my $self = shift;
	bless $self, $$self{default_mode}; # rebless default class
	print { $$self{OUT} } "\n";
	return undef unless defined $$self{_loop}; # exit application
	my $string = join("\n", @{$$self{lines}}) || '';
	$self->AddHistory($string) if $$self{config}{autohistory};
	return '' if $$self{config}{ignore_comment}
		and ! grep {$_ !~ /^\s*\Q$$self{config}{ignore_comment}\E/} @{$$self{lines}};
	$string =~ s/\\\n//ge if $$self{config}{automultiline};
	#print STDERR "string: $string\n";
	return $string;
}

sub addhistory {
	my ($self, $line) = @_;
	return unless defined $$self{config}{minline};
	return unless length $line and length($line) > $$self{config}{minline};
	unshift @{$$self{history}}, $line;
	$$self{hist_cnt}++;
}
*AddHistory = \&addhistory; # T:RL:Gnu compat

sub IN { $_[0]{IN} }

sub OUT { $_[0]{OUT} }

sub MinLine {
	my ($self, $minl) = @_;
	my $old_minl = $$self{config}{minline};
	$$self{config}{minline} = $minl;
	return $old_minl;
}

sub Attribs { $_[0]{config} }

sub Features { {
	( map {($_ => 1)} qw/appname minline attribs 
		addhistory addHistory getHistory getHistory TermSize/ ),
	( map {($_ => $_[0]{config}{$_})}
		qw/autohistory autoenv automultiline/ ),
} }

# ############ #
# Extended api #
# ############ #

sub GetHistory {
	return wantarray 
		? ( reverse @{$_[0]{history}} )
		: [ reverse @{$_[0]{history}} ] ;
}

sub SetHistory {
	my $self = shift;
	$self->{history} = ref($_[0]) ? $_[0] : [@_];
}

# TermSize in Base

sub continue { # user typed \n but app says we ain't done
	my $self = shift;
	shift @{$$self{history}} if $$self{history}[0] eq join "\n", @{$$self{lines}};
	$$self{_buffer}++; # previous _return printed a \n
	my $mode = $$self{mode};
	$self->switch_mode('multiline');
	$self->do_key("\n");
	$self->switch_mode($mode);
	$self->loop();
	return $self->_return();
}

sub current {
	return $_current if $_current;
	my (undef, $f, $l) = caller;
	die "No current Ter::ReadLine::Zoid object at $f line $l";
}

sub bindkey {
	my ($self, $key, $sub, $map) = @_;
	$map ||= 'default';
	if ($map eq 'default') { $$self{_key_map}{$key} = $sub }
	else { $$self{_key_map}{$map}{$key} = $sub }
}

# ############ #
# Internal api #
# ############ #

sub switch_mode {
	my ($self, $mode, @args) = @_;
	$mode ||= 'default';
	if ($mode eq 'default') {
		$$self{key_map} = $$self{_key_map};
		$$self{replace} = 0;
		bless $self, $$self{default_mode};
	}
	else {
		return warn "No such mode: $mode\n"
			unless exists $$self{_key_map}{$mode};
		$$self{key_map} = $$self{_key_map}{$mode};
		if (exists $$self{key_map}{_on_switch}) {
			my $class = $$self{key_map}{_on_switch}->(@args);
			return unless $class =~ /\w/;
			eval "use $class";
			die $@ if $@;
			bless $self, $class;
		}
	}
	$$self{mode} = $mode;
}

sub reset { # should this go in Base ?
	my $self = shift;
	$$self{lines} = [''];
	$$self{pos}  = [0, 0];
	$$self{_buffer} = 0;
	$$self{replace} = 0;
	$$self{hist_p} = undef;
	$$self{undostack} = [];
}

sub save {
	my $self = shift;
	my %save = (
		pos    => [ @{$$self{pos}}   ],
		lines  => [ @{$$self{lines}} ],
		prompt => $$self{prompt},
	);
	return \%save;
}

sub restore {
	my ($self, $save) = @_;
	$$self{pos}    = [ @{$$save{pos}} ];
	$$self{lines}  = [ @{$$save{lines}} ];
	$$self{prompt} = $$save{prompt};
}

sub hist_up {
	my $self = shift;
	if (not defined $$self{hist_p}) {
		return $self->bell unless scalar @{$$self{history}};
		$$self{_hist_save} = $self->save();
		$self->set_hist(0);
	}
	elsif ($$self{hist_p} < $#{$$self{history}}) {
		$self->set_hist( ++$$self{hist_p} );
	}
	else { return $self->bell }
	return 1;
}

sub hist_down {
	my $self = shift;
	return $self->bell unless defined $$self{hist_p};
	if ($$self{hist_p} == 0) {
		$$self{hist_p} = undef;
		$self->restore($$self{_hist_save});
	}
	else { $self->set_hist( --$$self{hist_p} ) }
	return 1;
}

sub set_hist { # make sure the index u ask for exists !
	my $self = shift;
	$$self{hist_p} = shift;
	$$self{lines} = [ split /\n/, $$self{history}[ $$self{hist_p} ] ];
	$$self{pos} = [ length($$self{lines}[-1]), $#{$$self{lines}} ];
	# posix says {pos} should be [0, 0], i disagree
}

# ######### #
# Render Fu #
# ######### #

sub draw {
	my $self  = shift;
	my @pos   = @{$$self{pos}};   # force copy
	my @lines = @{$$self{lines}}; # idem
#	use Data::Dumper; print STDERR Dumper \@lines, \@pos;

	$pos[0] = length $lines[ $pos[1] ]
		if $pos[0] > length $lines[ $pos[1] ];

	# replace the non printables
	for (0 .. $#lines) {
		if ($_ == $pos[1]) {
			my $start = substr $lines[$_], 0, $pos[0], '';
			my $n = ( $start =~ s{([^[:print:]])}{
				my $ord = ord $1;
				($ord < 32) ? '^'.(chr $ord + 64) : '^?'
			}ge );
			$pos[0] += $n;
			$lines[$_] = $start . $lines[$_];
		}
		$lines[$_] =~ s{([^[:print:]\e])}{
			my $ord = ord $1;
			($ord < 32) ? '^'.(chr $ord + 64) : '^?'
		}ge;
	}

	# render prompt - ugly "set nu" code by carl0s
	my $prompt = ref($$self{prompt}) ? ${$$self{prompt}} : $$self{prompt};
	my $ps2len = length(@lines) + 2; # reserved space for line numbers
	$prompt =~ s/(!!|!)/($1 eq '!!') ? '!' : $$self{hist_cnt}/eg;
	my @prompt = split /\n/, $prompt;
	@prompt = ('') unless @prompt;
	my $ps2 = ref($$self{config}{PS2}) ? ${$$self{config}{PS2}} : $$self{config}{PS2};
	$pos[0] += !$pos[1] ? $self->print_length($prompt[-1]) 
		: ( $self->print_length($ps2)  + ( $self->{config}{nu} ? $ps2len : 0 ) );
	$pos[1] += $#prompt;
	$lines[$_] =  (($self->{config}{nu} && $_) ? sprintf("\e[%dm% ${ps2len}d\e[0m ",33, $_ + 1) : '').$ps2.$lines[$_] for 1 .. $#lines;
	$lines[0] = pop(@prompt) . $lines[0];
	unshift @lines, @prompt if @prompt;

	# right prompt ... idea from zsh
	my $l = $self->print_length($lines[0]);
	my $rprompt = ref($$self{config}{RPS1}) ? ${$$self{config}{RPS1}} : $$self{config}{RPS1};
	if ($rprompt and $l < $$self{term_size}[0]) {
		$rprompt = substr $rprompt, - $$self{term_size}[0] + $l -1;
		$lines[0] .= (' 'x($$self{term_size}[0] - $l - $self->print_length($rprompt) -1)) . $rprompt;
	}

	$self->print(\@lines, \@pos);
}

# #################### #
# Default key bindings #
# #################### #

sub escape { $_[0]->switch_mode('command') }

sub ctrl_r { $_[0]->switch_mode('isearch') }

sub default {
	my ($self, $chr) = (@_);

	# force pos on end of line
	$$self{pos}[0] = length $$self{lines}[ $$self{pos}[1] ]
		if $$self{pos}[0] > length $$self{lines}[ $$self{pos}[1] ];

	# FIXME if non printable do something funky

	substr $$self{lines}[ $$self{pos}[1] ], $$self{pos}[0], $$self{replace}, $chr;
	$$self{pos}[0] += length $chr;
}

sub return {
	my $self = shift;
	if ( 
		$$self{config}{automultiline} and scalar @{$$self{lines}}
		and ! grep /\\\\$|(?<!\\)$/, @{$$self{lines}}
	) {  #print STDERR "funky auto multiline :)\n";
		push @{$$self{lines}}, '';
		$$self{pos} = [0, $#{$$self{lines}}];
	}
	else { $$self{_loop} = 0 }
}

sub ctrl_d {
	length( join "\n", @{$_[0]{lines}} ) 
		? ( $_[0]->bell ) 
		: ( $_[0]{_loop} = undef ) ;
}

sub ctrl_c { @{$_[0]}{'lines', '_loop'} = ([], 0) }

sub delete { # 1 char only !
	my $self = shift;

	if ($$self{pos}[0] >= length $$self{lines}[ $$self{pos}[1] ]) {
		$$self{pos}[0] = length $$self{lines}[ $$self{pos}[1] ]; # force pos on end of line
		return $self->bell unless $$self{pos}[1] < @{$$self{lines}};
		$$self{lines}[ $$self{pos}[1] ] .= $$self{lines}[ $$self{pos}[1] + 1 ]; # append next line
		splice @{$$self{lines}}, $$self{pos}[1] + 1, 1; # kill next line
	}
	else { substr $$self{lines}[ $$self{pos}[1] ], $$self{pos}[0], 1, '' }
	return 1;
}

sub backspace {
	$_[0]->left();
	$_[0]->delete() unless $_[0]{replace};
}

sub ctrl_u {
	$_[0]{killbuf} = join "\n", @{$_[0]{lines}};
	@{$_[0]}{'lines', 'pos'} = ([''], [0, 0])
}

sub tab {
	my ($self, undef, $preview) = @_;

	# check !autolist stuff
	if ($$self{completions} && @{$$self{completions}}) {
		$self->output( @{$$self{completions}} );
		delete $$self{completions};
		return;
	}

	# get the right function
	my $func = exists($$self{config}{completion_function}) 
		? $$self{config}{completion_function}
		: $readline::rl_completion_function ;
	return unless $func;
	unless (ref $func) {
		no strict;
		$func = *{$func}{CODE};
		return unless ref $func; # how does this work ?
	}

	# generate the arguments
	my $buffer = join "\n", @{$$self{lines}};
	my $end = $self->pos2off($$self{pos});
	my $word = substr $buffer, 0, $end;
	$word =~ s/^.*\s//s; # only leave /\S*$/
	my $lw = length $word;

	# get the completions and output
	my @compl = $func->($word, $buffer, $end - $lw); # word, line, start
	my $meta = ref($compl[0]) ? shift(@compl) : {} ; # hash constitutes an undocumented feature
	$self->output( $$meta{message} ) if $$meta{message};

	return $self->bell unless @compl;
	if ($compl[0] eq $compl[-1]) { @compl = ($compl[0]) } # 1 item or list with only duplicates
	else { @compl = $self->longest_match(@compl) } # returns $compl, @compl

	my $compl = shift @compl;
	$compl =~ s#\\\\|(?<!\\)($$meta{quoted})#$1?"\\$1":'\\\\'#ge if $$meta{quoted};
	$compl = $$meta{prefix} . $compl;
	if (@compl) {
		if ($$self{config}{autolist} || $preview) {
			$self->output( @compl );
			return if $preview;
		}
		else { $$self{completions} = \@compl }
		$compl =~ s#\\\\|(?<!\\)([^\w\-\./~])#$1?"\\$1":'\\\\'#eg
			unless $$meta{quoted};
	}
	else {
		$compl .= $$meta{postfix};
		$compl =~ s#\\\\|(?<!\\)([^\w\-\./~])#$1?"\\$1":'\\\\'#eg
			unless $$meta{quoted};
		$compl .= $$meta{quoted}.' ' if $compl =~ /\w$/; # arbitrary cruft
	}

	# update buffer
	push @{$$self{undostack}}, $self->save() if length $compl;
#	print STDERR ">>$buffer<< end $end off: ".($end - $lw)." l: $lw c: $compl\n";
	my $start = $$meta{start} || $end - $lw;
	substr $buffer,  $start, $end - $start, $compl;
	$$self{lines} = [ split /\n/, $buffer ];
	$$self{pos}[0] -= $lw - length($compl); # for the moment completions can't contains \n
}

sub longest_match { # cut doubles and find longest match
	my ($self, @compl) = @_;

	@compl = sort @compl;
	my $match = $compl[0];
	while ($match and $compl[-1] !~ /^\Q$match\E/) { chop $match } # due to sort only one diff

	my $prev = '';
	return ($match, grep {
		if ($_ eq $prev) { 0 }
		else { $prev = $_; 1 }
	} @compl);
}

sub insert {
	my $b = $_[0]{replace};
	$_[0]->switch_mode(); # for command mode
	$_[0]{replace} = $b ? 0 : 1;
}

sub right { # including cnt for vi mode
	my ($self, undef, $cnt) = @_;
	for (1 .. $cnt||1) {
		if ($$self{pos}[0] >= length $$self{lines}[ $$self{pos}[1] ]) {
			return $self->bell unless $$self{pos}[1] < $#{$$self{lines}};
			$$self{pos} = [0, ++$$self{pos}[1]];
		}
		else { $$self{pos}[0]++ }
	}
	return 1;
}

sub left { # including cnt for vi mode
	my ($self, undef, $cnt) = @_;
#	print STDERR "going $cnt left, pos $$self{pos}[0]\n";
	for (1 .. $cnt||1) {
		if ($$self{pos}[0] == 0) {
			return $self->bell if $$self{pos}[1] == 0;
			$$self{pos}[1]--;
			$$self{pos}[0] = length $$self{lines}[ $$self{pos}[1] ];
		}
		elsif ($$self{pos}[0] >= length $$self{lines}[ $$self{pos}[1] ]) {
			$$self{pos}[0] = length($$self{lines}[ $$self{pos}[1] ]) - 1;
		}
		else { $$self{pos}[0]-- }
	}
	return 1;
}

sub home { $_[0]{pos}[0] = 0; return 1 }

sub end { $_[0]{pos}[0] = length $_[0]{lines}[ $_[0]{pos}[1] ]; return 1 }

# define various aliases
*ctrl_b = \&left;
*ctrl_f = \&right;
*up     = \&hist_up;
*ctrl_p = \&hist_up;
*down   = \&hist_down;
*ctrl_n = \&hist_down;
*ctrl_a = \&home;
*ctrl_e = \&end;

sub ctrl_v {
	# FIXME set signals to ingnore (?)
	my $self = shift;
	$self->default($self->read_key);
}

sub ctrl_w {
	my $self = shift;
	$$self{pos}[0] = length $$self{lines}[ $$self{pos}[1] ]
		if $$self{pos}[0] > length $$self{lines}[ $$self{pos}[1] ];
	my $pre = substr $$self{lines}[ $$self{pos}[1] ], 0, $$self{pos}[0], '';
	$pre =~ s/\S*\s*$//;
	$$self{pos}[0] = length $pre;
	$$self{lines}[ $$self{pos}[1] ] = $pre . $$self{lines}[ $$self{pos}[1] ];
}

sub ctrl_l { $_[0]->cls() }

sub ctrl_k {
	my $self = shift;
	$$self{lines}[ $$self{pos}[1] ] = substr $$self{lines}[ $$self{pos}[1] ], 0, $$self{pos}[0];
}

1;

__END__

=head1 NAME

Term::ReadLine::Zoid - another ReadLine package

=head1 SYNOPSIS

	# In your app:
	use Term::ReadLine;
	my $term = Term::ReadLine->new("my app");
	
	my $prompt = "eval: ";
	my $OUT = $term->OUT || \*STDOUT;
	while ( defined ($_ = $term->readline($prompt)) ) {
		# Think while (<STDIN>) {}
		my $res = eval($_);
		warn $@ if $@;
		print $OUT $res, "\n" unless $@;
	}
	
	# In some rc file
	export PERL_RL=Zoid

=head1 DESCRIPTION

This package provides a set of modules that form an interactive input buffer
written in plain perl with minimal dependencies. It features almost all
key-bindings described in the posix spec for the sh(1) utility with some extensions like
multiline editing; this includes a vi-command mode with a save-buffer
(for copy-pasting) and an undo-stack.

Historically this code was part of the Zoidberg shell, but this implementation
is complete independent from zoid and uses the  L<Term::ReadLine> interface, so it
can be used with other perl programs.

=head1 ENVIRONMENT

The L<Term::ReadLine> interface module uses the C<PERL_RL> variable
to decide which module to load; so if you want to use this module for all
your perl applications, try something like:

	export PERL_RL=Zoid

=head1 KEY MAPPING

The default key mapping is as follows:

=over 4

=item escape

=item ^[

Place the line editor in command mode, see L<Term::ReadLine::Zoid::ViCommand>.

=item ^C

End editing and return an empty string.

=item ^D

End editing and return C<undef>.
Disabled when there are any chars on the edit line.

=item delete

=item backspace

=item ^H

=item ^?

Delete and backspace kill the current or previous character.
The key '^?' is by default considered a backspace because most modern
keyboards use this key for the "backspace" key and an escape sequence
for the "delete" key.
Of course '^H' is also considered a backspace.

=item tab

=item ^I

Try to complete the bigword on left of the cursor.

There is no default completion included in this package, so unless you define a custom
expansion it doesn't do anything. See the L<completion_function> option.

=item return

=item ^J

End editing and return the edit line to the application unless the newline is escaped.

If _all_ lines in the buffer end with a single '\', the newline is considered escaped
you can continue typing on the next line. This behaviour can be a bit unexpected
because this module has multiline support which historic readline implementations
have not, historically the escaping of a newline is done by the application not by the library.
The surpress this behaviour, and let the application do it's thing, disable the "automultiline"
option.

To enter the real multiline editing mode, press 'escape m',
see L<Term::ReadLine::Zoid::MultiLine>.

=item ^K

Delete from cursor to the end of the line.

=item ^L

Clear entire screen.

=item ^R

Enter incremental search mode, see L<Term::ReadLine::Zoid::ISearch>.

=item ^U

This is also known as the "kill" char. It deletes all characters on the edit line
and puts them in the save buffer. You can paste them back in later with 'escape-p'.

=item ^V

Insert next key literally, ignoring any key-bindings.

WARNING: control or escape chars in the editline can cause unexpected results

=item ^W

Delete the word before the cursor.

=item insert

Toggle replace bit.

=item ^A

=item home

Move cursor to the begin of the edit line.

=item ^E

=item end

Move cursor to the end of the edit line.

=item ^B

=item left

=item ^F

=item right

These keys can be used to move the cursor in the edit line.

=item ^P

=item up

=item ^N

=item down

These keys are used to rotate the history.

=back

=head1 ATTRIBS

The hash with options can be accessed with the L<Attribs> method.
Also they can be altered interactively using the mini-buffer of the command mode.

=over 4

=item autohistory

If enabled lines are added to the history automaticly,
subject to L<MinLine>. By default enabled.

=item autoenv

If enabled the environment variables C<COLUMNS> and C<LINES>
are kept up to date. By default enabled.

=item autolist

If set completions are listed directly when a completion fails,
if not set you need to press "tab" twice to see a list of possible completions.
By default enabled.

=item automultiline

See L<return> for a description. By default enabled.

=item bell

This option can contain a CODE reference.
The default is C<print "\cG">, which makes the terminal ring a bell.

=item completion

TODO private completion hook

=item completion_function

This option can contain either a code ref or the name of a function to perform
completion. For compatibility with Term::ReadLine::Perl the global scalar
C<$readline::rl_completion_function> will be checked if this option
isn't defined.

The function will get the following arguments: C<$word>, C<$buffer>, C<$start>.
Where C<$word> is the word before the cursor, while C<$buffer> is the complete text
on the command line; C<$start> is the offset of C<$word> in C<$buffer>. 

The function should return a list of possible completions of C<$word>.
The completion list is checked for double entries.

There is B<no> default.

=item ignore_comment

This option can be set to a string, if the edit line starts with this string the line
is regarded to be a comment and is not returned to the application, but it will appear
in the history if 'autohistory' is also set. Defaults to "#".

When there are multiple lines in the buffer they all need to start with the comment
string for the buffer to be regarded as a comment.

=item maxcomplete

Maximum number of completions to be displayed. By default set to 150.

=item minline

This option controls which lines are included in the history, lines
shorter then this number are ignored. When set to "0" all lines are included in the
history, when set to C<undef> all lines are ignored.
Defaults to "0".

=item PS2

This option can contain the prompt to be used for extra buffer lines.
It defaults to C<< "> " >>.

Although the "PS1" prompt (as specified as an argument to the C<readline()> method)
can contain newlines, the PS2 prompt can't.

=item RPS1

This option can contain a string that will be shown on the right side of the screen.
This is known as the "right prompt" and the idea is stolen from zsh(1).

=item title

Used to set the terminal title, defaults to the appname.

=item low_latency

Changes the escape sequences are read from input.
If true delays evalution of the escape key till the next char is known.
By default disabled.

=back

=head1 FILES

This module reads a rc-file on intialisation, either F<$HOME/.perl_rl_zoid_rc>,
F<$HOME/.zoid/perl_rl_zoid_rc> or F</etc/perl_rl_zoid_rc>.
The rc-file is a perl script with access to the Term::ReadLine::Zoid object through
the method C<current()>.
If you want to have different behaviour for different applications,
try to check for C<< $rl->{appname} >>.

	# in for example ~/.perl_rl_zoid_rc
	my $rl = Term::ReadLine::Zoid->current();
	
	# set low latency
	$rl->Attribs()->{low_latency} = 1;
	
	# alias control-space to escape
	$rl->bindchr( chr(0), 'escape' );
	
	# create an ad hoc macro
	$rl->bindkey('^P', sub { $rl->press('mplayer -vo sdl ') } );

=head1 METHODS

=head2 ReadLine api

Functions specified by the L<Term::ReadLine> documentation.

=over 4

=item C<new($appname, $IN, $OUT)>

Simple constructor. Arguments are the application name (used for default prompt
and title string) and optional filehandles for input and output.

=item C<ReadLine()>

Returns the name of the current ReadLine module actually used.

=item C<readline($prompt, $preput)>

Returns a string entered by the user. 
The final newline is stripped, though the string might contain newlines elsewhere.

The prompt only supports the escape "!" for the history number
of the current line, use "!!" for a literal "!".
All other escapes you need to parse yourself, before supplying
the prompt.
The prompt defaults to C<< "$appname !> " >>.

If you want to do more with your prompt see L<Env::PS1>.

C<$preput> can be used to set some text on the edit line allready.

=item C<addhistory($line)>

=item C<AddHistory($line)>

Add a command to the history (subject to the L<minline> option).

If L<autohistory> is set this method will be called automaticly by L<readline>.

=item C<IN()>

Returns the filehandle used for input.

=item C<OUT()>

Returns the filehandle used for output.

=item C<MinLine($value)>

Sets L<minline> option to C<$value> and returns old value.

=item C<findConsole()>

TODO - what uses does this have ?

=item C<Attribs()>

Returns a reference to the options hash.

=item C<Features()>

Returns a reference to a hash with names of implemented features.

Be aware that the naming scheme is quite arbitrary, this module
uses the same names as Term::ReadLine::Gnu for common features.

=back

=head2 Extended api

=over 4

=item C<SetHistory(@hist)>

=item C<GetHistory()>

Simple acces to the history arry, the "set" function supports both a list
and a reference, the "get" function uses "wantarray".
Not sure which behaviour is compatible with T:RL::Gnu.

=item C<TermSize()>

Returns number of columns and lines on the terminal.

=item C<continue()>

This method can be called to continue the previous C<readline()> call.
Can be used to build a custom auto-mulitline feature.

=item C<current()>

Returns the current T:RL::Zoid object, for use in rc files, see L<FILES>.

=item C<bindkey($key, $sub, $map)>

Bind a CODE reference to a key, the function gets called when the key is typed with
the key name as an argument. The C<$map> argument is optional and can be either
"default", "command", "isearch" or "multiline".

If C<$sub> is not a reference it is considered an alias;
these aliases are not recursive.

For alphanumeric characters the name is the character itself, special characters have
long speaking names and control characters are prefixed with a '^'.

Binding combination with the meta- or alt-key is not supported.

=back

=head2 Private api

Methods for use in overload classes.

I<Avoid using these methods from the application.>

=over 4

=item C<switch_mode($mode)>

Switch to input mode C<$mode>; changes the key map and
reblesses the object if the C<_on_switch> key returns a class name.

=item C<reset()>

Reset all temporary attributes.

=item C<save()>

Returns a ref with a copy of some temporary attributes.
Can be used to switch between multiple edit lines in combination with L<restore>.

=item C<restore($save)>

Restores saved attributes.

=item C<hist_up()>

Scroll one position backwards in the history and display it in the buffer.

=item C<hist_down()>

Scroll one position forwards in the history and display it in the buffer.

=back

=head1 NOTES

With most modern keymappings the combination of the meta key (alt) with a letter
is identical with an escape character followed by that letter.

Some functioality may in time be moved to the ::Base package.

=head1 TODO

UTF8 support, or general charset support, would be nice but at the moment
I lack the means to test these things. If anyone has ideas or suggestions about this
please contact me.

=head1 BUGS

Line wrap doesn't always displays the last character on the line right, no functional bug though.

Please mail the author if you find any other bugs.

=head1 AUTHOR

Jaap Karssenberg || Pardus [Larus] E<lt>pardus@cpan.orgE<gt>

Copyright (c) 2004 Jaap G Karssenberg. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<Term::ReadLine::Zoid::ViCommand>,
L<Term::ReadLine::Zoid::MultiLine>,
L<Term::ReadLine::Zoid::ISearch>,
L<Term::ReadLine::Zoid::Base>,
L<Term::ReadLine>,
L<Env::PS1>,
L<Zoidberg>

=cut

