package Term::ReadLine::Zoid::ISearch;

use strict;
use base 'Term::ReadLine::Zoid';
no warnings; # undef == '' down here

our $VERSION = 0.01;

# sub _on_switch {
# 	$$self{is_lock} = undef;
# 	$$self{is_save} = [[''], [0,0], undef];
# 	return 'Term::ReadLine::Zoid::ISearch';
# }

sub draw { # rendering this inc mode is kinda consuming
	my ($self, @args) = @_;
	my $save = $self->save();
	my $string = join "\n", @{$$self{lines}};
	$$self{prompt} = "i-search qr($string): ";
	goto DRAW unless length $string;

	my ($result, $match, $hist_p) = (undef, '', -1);
	$$self{last_search} = ['b', $string];
	my $reg = eval { qr/^(.*?$string)/ };
	goto DRAW if $@;

	for (@{$$self{history}}) {
		$hist_p++;
		next unless $_ =~ $reg;
		($result, $match) = ($_, $1);
		last;
	}

	if (defined $result) {
		push @{$$self{last_search}}, $hist_p;
		$$self{is_lock} = undef;
		$$self{lines} = [ split /\n/, $result ];
		my @match = split /\n/, $match;
		$$self{pos} = [length($match[-1]), $#match];
		$$self{is_save} = [ $$self{lines}, $$self{pos}, $hist_p];
	}
	else { $$self{is_lock} = 1 }

	DRAW: Term::ReadLine::Zoid::draw($self, @args);
	$self->restore($save);
}

sub default {
	if ($_[0]{is_lock}) { $_[0]->bell }
	else { goto \&Term::ReadLine::Zoid::default }
}

sub escape {
	@{$_[0]}{qw/lines pos hist_p/} = @{$_[0]{is_save}};
	$_[0]->switch_mode();
	$_[0]->do_key('escape');
}

sub _switch_back {
	my ($self, $key) = @_;
	$$self{_hist_save} = $self->save();
	@$self{qw/lines pos hist_p/} = @{$$self{is_save}};
	$self->switch_mode();
	$self->do_key($key);
}

# make some aliases
no strict 'refs';
*{$_} = \&_switch_back for qw/left right home end up down return ctrl_u/;

sub backspace { # overrule the left alias
	Term::ReadLine::Zoid::left($_[0]);
	$_[0]->delete();
}

1;

__END__

=head1 NAME

Term::ReadLine::Zoid::ISearch - a readline incremental search mode

=head1 SYNOPSIS

This class is used as a mode under L<Term::ReadLine::Zoid>,
see there for usage details.

=head1 DESCRIPTION

This mode is intended as a work alike for the incremental search
found in the gnu readline library.

In this mode the string you enter is regarded as a B<perl regex> which is used
to do an incremental histroy search.
Special keys like movements or the C<return> drop you out of this mode
and set the edit line to the last search result.

=head1 AUTHOR

Jaap Karssenberg || Pardus [Larus] E<lt>pardus@cpan.orgE<gt>

Copyright (c) 2004 Jaap G Karssenberg. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

=cut

