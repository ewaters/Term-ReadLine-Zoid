use strict;
use Test::More tests => 30;
use Term::ReadLine::Zoid;

$|++;

# C<new($appname, $IN, $OUT)>

$ENV{PERL_RL} = 'Zoid';
if (eval 'use Term::ReadLine; 1') {
	my $t = Term::ReadLine->new('test');
	ok $t->ReadLine eq 'Term::ReadLine::Zoid', 'rl:zoid loaded';
}
else { ok 1, 'skip Term::ReadLine NOT installed, this might be a problem.' }

my $t = Term::ReadLine::Zoid->new('test');
$t->{config}{bell} = sub {}; # Else the "\cG" fucks up test harness

# test routines
sub test_reset {
	$_[0]->reset();
	$_[0]->{lines} = [ 'duss ja', 'nou ja', 'test 123' ]; # 3 X 7,6,8
	$_[0]->{pos} = [5, 1];
}

# delete &&  backspace
test_reset $t;
$t->delete;
$t->delete;
ok $t->{lines}[1] eq 'nou jtest 123', 'delete \n';

test_reset $t;
$t->press("\c?\c?\c?");
ok $t->{lines}[1] eq 'noa', 'backspace';

# control-U
test_reset $t;
$t->press("\cU");
is_deeply $t->{lines}, [''], '^U';

# left && right
test_reset $t;
ok $t->right, 'right 1';
ok $t->right, 'right 2';
is_deeply $t->{pos}, [0,2], 'pos 1';
ok $t->left, 'left 1';
is_deeply $t->{pos}, [6,1], 'pos 2';
$t->left for 1 .. 14; # 6 + \n + 7
is_deeply $t->{pos}, [0,0], 'pos 3';
ok ! $t->left(), 'left 2';
$t->{pos} = [8, 2];
ok ! $t->right(), 'right 3';

# up && down
$t->{lines} = [ 'entry0' ];
$t->{history} = ['entry1', "entry2\ntest123", 'entry3'];
$t->up; $t->up;
is_deeply $t->{lines}, ['entry2', 'test123'], 'hist 1';
$t->up;
ok $t->{lines}[0] eq 'entry3', 'hist 2';
ok ! $t->up, 'hist 3';
$t->down; $t->down;
ok $t->{lines}[0] eq 'entry1', 'hist 4';
$t->down;
ok $t->{lines}[0] eq 'entry0', 'hist 5';
ok ! $t->down, 'hist 6';

# control-W
$t->{lines} = ['word1 word2 word3'];
$t->{pos} = [13, 0];
$t->press("\cW");
ok $t->{lines}[0] eq 'word1 word2 ord3', '^W 1';
$t->press("\cW");
ok $t->{lines}[0] eq 'word1 ord3', '^W 2';

# control-V
@$t{'pos','lines'} = ([0,0], ['']);
push @Term::ReadLine::Zoid::Base::_key_buffer, "\cV", "\cW";
$t->do_key();
ok $t->{lines}[0] eq "\cW", '^V';

# save and restore
test_reset $t;
my $save = $t->save();
$t->{lines} = ['duss', 'ja'];
$t->{pos} = [333,444];
$t->restore($save);
is_deeply [[ 'duss ja', 'nou ja', 'test 123' ], [5, 1]], [@$t{'lines', 'pos'}], 'save n restore';

# escape
$t->press("\e");
ok ref($t) eq 'Term::ReadLine::Zoid::ViCommand', 'escape to command mode';

if (eval 'Term::ReadKey::GetTerminalSize() and 1') {
	# readline && continue
	my $prompt = "# readline() test !> "; # Test::Harness might choke without the "#"
	$t->unread_key("test 1 2 3\n");
	ok $t->readline($prompt) eq 'test 1 2 3', 'readline \n';

	$t->unread_key("test\cH\cH\cH\cH\cD");
	ok ! defined( $t->readline($prompt) ), 'readline \cD';

	$t->unread_key("test 1 2 3\cC");
	ok $t->readline($prompt) eq '', 'readline \cC';

	$t->Attribs()->{PS2} = "# ps2> ";
	$t->unread_key("test 1 2 3\n");
	$t->readline($prompt);
	$t->unread_key("ok\n");
	ok $t->continue() eq "test 1 2 3\nok", 'readline continue';
}
else {
	ok 1, 'skip - No TermSize, cross your fingers' for 1 .. 4;
}

# bindkey() and bindchr()
$t->switch_mode();

test_reset $t;
$t->bindchr('^B', 'backspace');
$t->press("\cB\cB\cB");
ok $t->{lines}[1] eq 'noa', 'bindchr';

test_reset $t;
$t->bindkey('^Q', sub { $t->press('abc') });
$t->press("\cQ");
ok $t->{lines}[1] eq 'nou jabca', 'bindkey';

test_reset $t;
$t->bindkey('backspace', '^Q');
$t->press("\cB");
ok $t->{lines}[1] eq 'nou jabca', 'bindkey scalar';

