
use strict;
use Test::More tests => 17;
use Term::ReadLine::Zoid::ViCommand;

# substring($string, $start, $end)

my $obj = Term::ReadLine::Zoid::MultiLine->new('test');
$obj->{lines} = ['test 123, dit is test data'] ;

$obj->substring('dus ', [17,0]);
ok( $$obj{lines}[0] eq 'test 123, dit is dus test data', 'simple insert');

$obj->substring("\nduss ", [30,0]);
$obj->substring('ja', [5,1]);

is_deeply(
	$$obj{lines},
	['test 123, dit is dus test data', 'duss ja'],
	'more inserts'
);

my $re = $obj->substring(undef, [21,0], [30,0]);
ok( ($re eq 'test data') && ($$obj{lines}[0] eq 'test 123, dit is dus test data'), 'copy');

$re = $obj->substring('een test', [21,0], [30,0]);
ok( ($re eq 'test data') && ($$obj{lines}[0] eq 'test 123, dit is dus een test'), 'simple replace');

$re = $obj->substring(",\ntest 123, test 123 .. ok", [29,0], [4,1]);
is_deeply(
	[$re, $$obj{lines}],
	["\nduss", ['test 123, dit is dus een test,', 'test 123, test 123 .. ok ja'] ],
	'multiline replace');

push @{$$obj{lines}}, '?';
$re = $obj->substring('', [27,1], [0,2]);
ok( ($re eq "\n") && ($$obj{lines}[1] eq 'test 123, test 123 .. ok ja?'), 'delete \n');

$obj->{lines} = ['test 123'];
$obj->substring(" duss\n", [8,0]);
is_deeply $obj->{lines}, ['test 123 duss', ''], 'insert empty line';

# up & down -- very simple regression test

$$obj{lines} = [
'test 123, dit is dus een test',
'test 123, test 123 .. ok ja?',
'test 123' ];

$obj->{pos} = [5, 0];
ok ! $obj->up, 'up 1';
ok $obj->down, 'down 1';
ok $obj->down, 'down 2';
is_deeply $obj->{pos}, [5, 2], 'pos 1';
ok ! $obj->down, 'down 3';
ok ! $obj->down, 'down 4';
ok $obj->up, 'up 2';
ok $obj->up, 'up 3';
ok !$obj->up, 'up 4';
is_deeply $obj->{pos}, [5, 0], 'pos 2';
