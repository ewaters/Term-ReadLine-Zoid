package Term::ReadLine::Zoid::MultiLine;

use strict;
use base 'Term::ReadLine::Zoid';
no warnings; # undef == '' down here

our $VERSION = 0.01;

sub substring { # buffer is undef is copy, end is undef is insert
	my ($self, $buffer, $start, $end) = @_;

	($start, $end) = sort {$$a[1] <=> $$b[1] or $$a[0] <=> $$b[0]} ($start, $end) if $end;
	my ($pre, $post) = _split($start || $$self{pos}, [ @{$$self{lines}} ]); # force copy of lines
	my $re = [''];
	if ($end) {
		$$end[0] = $$end[0] - $$start[0] if $$end[1] == $$start[1];
		$$end[1] = $$end[1] - $$start[1];
		($re, $post) = _split($end, $post);
	}
	return join "\n", @$re unless defined $buffer;

	$buffer = [split /\n/, $buffer, -1] if ! ref $buffer;
	$buffer = [''] unless @$buffer;
	$$pre[-1] .= shift @$buffer;
	push @$pre, @$buffer;
	$$self{pos} = [ length($$pre[-1]), $#$pre ];
	$$pre[-1] .= shift @$post;
	$$self{lines} = [ @$pre, @$post ];

	return join "\n", @$re;
}

sub _split {
	my ($pos, $buf, $nbuf) = (@_, []);
	push @$nbuf, splice @$buf, 0, $$pos[1] if $$pos[1];
	push @$nbuf, substr($$buf[0], 0, $$pos[0], '') || '';
	return ($nbuf, $buf);
}

# ############ #
# Key bindings #
# ############ #

sub return {
	my $self = shift;
	my $l = length $$self{lines}[ $$self{pos}[1] ];
	my $end = substr $$self{lines}[ $$self{pos}[1] ], $$self{pos}[0], $l, '';
	$$self{pos} = [0, $$self{pos}[1] + 1];
	splice @{$$self{lines}}, $$self{pos}[1], 0, $end || '';
}

sub up {
	my $self = shift;
	return 0 unless $$self{pos}[1] > 0;
	$$self{pos}[1]--;
	return 1;
}

sub down {
	my $self = shift;
	return 0 unless $$self{pos}[1] < $#{$$self{lines}};
	$$self{pos}[1]++;
	return 1;
}

1;

__END__

=head1 NAME

Term::ReadLine::Zoid::MultiLine - a readline multiline edit mode

=head1 SYNOPSIS

This class is used as a mode under L<Term::ReadLine::Zoid>,
see there for usage details.

=head1 DESCRIPTION

You can enter this mode by pressing C<escape> to enter command mode and then press C<m>.
When in multiline mode the behaviour of the return and the up and down arrows is different.
To execute the edit buffer press C<escape> to enter command mode
again and then press C<return>.

=head1 AUTHOR

Jaap Karssenberg || Pardus [Larus] E<lt>pardus@cpan.orgE<gt>

Copyright (c) 2004 Jaap G Karssenberg. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

=cut

