#! /usr/bin/env perl
# Path.t -- tests for module File::Path

use strict;

use Test::More tests => 127;
use Config;
use Fcntl ':mode';
use lib 't/';
use FilePathTest;

BEGIN {
    use_ok('Cwd');
    use_ok('File::Path', qw(rmtree mkpath make_path remove_tree));
    use_ok('File::Spec::Functions');
}

my $Is_VMS = $^O eq 'VMS';

# first check for stupid permissions second for full, so we clean up
# behind ourselves
for my $perm (0111,0777) {
    my $path = catdir(curdir(), "mhx", "bar");
    mkpath($path);
    chmod $perm, "mhx", $path;

    my $oct = sprintf('0%o', $perm);

    ok(-d "mhx", "mkdir parent dir $oct");
    ok(-d $path, "mkdir child dir $oct");

    rmtree("mhx");

    ok(! -e "mhx", "mhx does not exist $oct");
}

# find a place to work
my ($error, $list, $file, $message);
my $tmp_base = catdir(
    curdir(),
    sprintf( 'test-%x-%x-%x', time, $$, rand(99999) ),
);

# invent some names
my @dir = (
    catdir($tmp_base, qw(a b)),
    catdir($tmp_base, qw(a c)),
    catdir($tmp_base, qw(z b)),
    catdir($tmp_base, qw(z c)),
);

# create them
my @created = mkpath([@dir]);

is(scalar(@created), 7, "created list of directories");

# pray for no race conditions blowing them out from under us
@created = mkpath([$tmp_base]);
is(scalar(@created), 0, "skipped making existing directory")
    or diag("unexpectedly recreated @created");

# create a file
my $file_name = catfile( $tmp_base, 'a', 'delete.me' );
my $file_count = 0;
if (open OUT, "> $file_name") {
    print OUT "this file may be deleted\n";
    close OUT;
    ++$file_count;
}
else {
    diag( "Failed to create file $file_name: $!" );
}

SKIP: {
    skip "cannot remove a file we failed to create", 1
        unless $file_count == 1;
    my $count = rmtree($file_name);
    is($count, 1, "rmtree'ed a file");
}

@created = mkpath('');
is(scalar(@created), 0, "Can't create a directory named ''");

my $dir;
my $dir2;

sub gisle {
    # background info: @_ = 1; !shift # gives '' not 0
    # Message-Id: <3C820CE6-4400-4E91-AF43-A3D19B356E68@activestate.com>
    # http://www.nntp.perl.org/group/perl.perl5.porters/2008/05/msg136625.html
    mkpath(shift, !shift, 0755);
}

sub count {
    opendir D, shift or return -1;
    my $count = () = readdir D;
    closedir D or return -1;
    return $count;
}

{
    mkdir 'solo', 0755;
    chdir 'solo';
    open my $f, '>', 'foo.dat';
    close $f;
    my $before = count(curdir());
    cmp_ok($before, '>', 0, "baseline $before");

    gisle('1st', 1);
    is(count(curdir()), $before + 1, "first after $before");

    $before = count(curdir());
    gisle('2nd', 1);

    is(count(curdir()), $before + 1, "second after $before");

    chdir updir();
    rmtree 'solo';
}

{
    mkdir 'solo', 0755;
    chdir 'solo';
    open my $f, '>', 'foo.dat';
    close $f;
    my $before = count(curdir());

    cmp_ok($before, '>', 0, "ARGV $before");
    {
        local @ARGV = (1);
        mkpath('3rd', !shift, 0755);
    }

    is(count(curdir()), $before + 1, "third after $before");

    $before = count(curdir());
    {
        local @ARGV = (1);
        mkpath('4th', !shift, 0755);
    }

    is(count(curdir()), $before + 1, "fourth after $before");

    chdir updir();
    rmtree 'solo';
}

SKIP: {
    # tests for rmtree() of ancestor directory
    my $nr_tests = 6;
    my $cwd = getcwd() or skip "failed to getcwd: $!", $nr_tests;
    my $dir  = catdir($cwd, 'remove');
    my $dir2 = catdir($cwd, 'remove', 'this', 'dir');

    skip "failed to mkpath '$dir2': $!", $nr_tests
        unless mkpath($dir2, {verbose => 0});
    skip "failed to chdir dir '$dir2': $!", $nr_tests
        unless chdir($dir2);

    rmtree($dir, {error => \$error});
    my $nr_err = @$error;

    is($nr_err, 1, "ancestor error");

    if ($nr_err) {
        my ($file, $message) = each %{$error->[0]};

        is($file, $dir, "ancestor named");
        my $ortho_dir = $^O eq 'MSWin32' ? File::Path::_slash_lc($dir2) : $dir2;
        $^O eq 'MSWin32' and $message
            =~ s/\A(cannot remove path when cwd is )(.*)\Z/$1 . File::Path::_slash_lc($2)/e;

        is($message, "cannot remove path when cwd is $ortho_dir", "ancestor reason");

        ok(-d $dir2, "child not removed");

        ok(-d $dir, "ancestor not removed");
    }
    else {
        fail( "ancestor 1");
        fail( "ancestor 2");
        fail( "ancestor 3");
        fail( "ancestor 4");
    }
    chdir $cwd;
    rmtree($dir);

    ok(!(-d $dir), "ancestor now removed");
};

my $count = rmtree({error => \$error});

is( $count, 0, 'rmtree of nothing, count of zero' );

is( scalar(@$error), 0, 'no diagnostic captured' );

@created = mkpath($tmp_base, 0);

is(scalar(@created), 0, "skipped making existing directories (old style 1)")
    or diag("unexpectedly recreated @created");

$dir = catdir($tmp_base,'C');
# mkpath returns unix syntax filespecs on VMS
$dir = VMS::Filespec::unixify($dir) if $Is_VMS;
@created = make_path($tmp_base, $dir);

is(scalar(@created), 1, "created directory (new style 1)");

is($created[0], $dir, "created directory (new style 1) cross-check");

@created = mkpath($tmp_base, 0, 0700);

is(scalar(@created), 0, "skipped making existing directories (old style 2)")
    or diag("unexpectedly recreated @created");

$dir2 = catdir($tmp_base,'D');
# mkpath returns unix syntax filespecs on VMS
$dir2 = VMS::Filespec::unixify($dir2) if $Is_VMS;
@created = make_path($tmp_base, $dir, $dir2);

is(scalar(@created), 1, "created directory (new style 2)");

is($created[0], $dir2, "created directory (new style 2) cross-check");

$count = rmtree($dir, 0);

is($count, 1, "removed directory unsafe mode");

$count = rmtree($dir2, 0, 1);
my $removed = $Is_VMS ? 0 : 1;

is($count, $removed, "removed directory safe mode");

# mkdir foo ./E/../Y
# Y should exist
# existence of E is neither here nor there
$dir = catdir($tmp_base, 'E', updir(), 'Y');
@created =mkpath($dir);

cmp_ok(scalar(@created), '>=', 1, "made one or more dirs because of ..");

cmp_ok(scalar(@created), '<=', 2, "made less than two dirs because of ..");

ok( -d catdir($tmp_base, 'Y'), "directory after parent" );

@created = make_path(catdir(curdir(), $tmp_base));

is(scalar(@created), 0, "nothing created")
    or diag(@created);

$dir  = catdir($tmp_base, 'a');
$dir2 = catdir($tmp_base, 'z');

rmtree( $dir, $dir2,
    {
        error     => \$error,
        result    => \$list,
        keep_root => 1,
    }
);


is(scalar(@$error), 0, "no errors unlinking a and z");

is(scalar(@$list),  4, "list contains 4 elements")
    or diag("@$list");

ok(-d $dir,  "dir a still exists");

ok(-d $dir2, "dir z still exists");

$dir = catdir($tmp_base,'F');
# mkpath returns unix syntax filespecs on VMS
$dir = VMS::Filespec::unixify($dir) if $Is_VMS;

@created = mkpath($dir, undef, 0770);

is(scalar(@created), 1, "created directory (old style 2 verbose undef)");

is($created[0], $dir, "created directory (old style 2 verbose undef) cross-check");

is(rmtree($dir, undef, 0), 1, "removed directory 2 verbose undef");

@created = mkpath($dir, undef);

is(scalar(@created), 1, "created directory (old style 2a verbose undef)");

is($created[0], $dir, "created directory (old style 2a verbose undef) cross-check");

is(rmtree($dir, undef), 1, "removed directory 2a verbose undef");

@created = mkpath($dir, 0, undef);

is(scalar(@created), 1, "created directory (old style 3 mode undef)");

is($created[0], $dir, "created directory (old style 3 mode undef) cross-check");

is(rmtree($dir, 0, undef), 1, "removed directory 3 verbose undef");

$dir = catdir($tmp_base,'G');
$dir = VMS::Filespec::unixify($dir) if $Is_VMS;

@created = mkpath($dir, undef, 0200);

is(scalar(@created), 1, "created write-only dir");

is($created[0], $dir, "created write-only directory cross-check");

is(rmtree($dir), 1, "removed write-only dir");

# borderline new-style heuristics
if (chdir $tmp_base) {
    pass("chdir to temp dir");
}
else {
    fail("chdir to temp dir: $!");
}

$dir   = catdir('a', 'd1');
$dir2  = catdir('a', 'd2');

@created = make_path( $dir, 0, $dir2 );

is(scalar @created, 3, 'new-style 3 dirs created');

$count = remove_tree( $dir, 0, $dir2, );

is($count, 3, 'new-style 3 dirs removed');

@created = make_path( $dir, $dir2, 1 );

is(scalar @created, 3, 'new-style 3 dirs created (redux)');

$count = remove_tree( $dir, $dir2, 1 );

is($count, 3, 'new-style 3 dirs removed (redux)');

@created = make_path( $dir, $dir2 );

is(scalar @created, 2, 'new-style 2 dirs created');

$count = remove_tree( $dir, $dir2 );

is($count, 2, 'new-style 2 dirs removed');

$dir = catdir("a\nb", 'd1');
$dir2 = catdir("a\nb", 'd2');

SKIP: {
  # Better to search for *nix derivatives?
  # Not sure what else doesn't support newline in paths
  skip "This is a MSWin32 platform", 2
    if $^O eq 'MSWin32';

  @created = make_path( $dir, $dir2 );

  is(scalar @created, 3, 'new-style 3 dirs created in parent with newline');

  $count = remove_tree( $dir, $dir2 );

  is($count, 2, 'new-style 2 dirs removed in parent with newline');
}

if (chdir updir()) {
    pass("chdir parent");
}
else {
    fail("chdir parent: $!");
}

SKIP: {
    # test bug http://bugs.debian.org/cgi-bin/bugreport.cgi?bug=487319
    skip "Don't need Force_Writeable semantics on $^O", 6
        if grep {$^O eq $_} qw(amigaos dos epoc MSWin32 MacOS os2);
    skip "Symlinks not available", 6 unless $Config{d_symlink};
    $dir  = 'bug487319';
    $dir2 = 'bug487319-symlink';
    @created = make_path($dir, {mask => 0700});

    is( scalar @created, 1, 'bug 487319 setup' );
    symlink($dir, $dir2);

    ok(-e $dir2, "debian bug 487319 setup symlink") or diag($dir2);

    chmod 0500, $dir;
    my $mask_initial = (stat $dir)[2];
    remove_tree($dir2);

    my $mask = (stat $dir)[2];

    is( $mask, $mask_initial, 'mask of symlink target dir unchanged (debian bug 487319)');

    # now try a file
    #my $file = catfile($dir, 'file');
    my $file  = 'bug487319-file';
    my $file2 = 'bug487319-file-symlink';
    open my $out, '>', $file;
    close $out;

    ok(-e $file, 'file exists');

    chmod 0500, $file;
    $mask_initial = (stat $file)[2];

    symlink($file, $file2);

    ok(-e $file2, 'file2 exists');
    remove_tree($file2);

    $mask = (stat $file)[2];

    is( $mask, $mask_initial, 'mask of symlink target file unchanged (debian bug 487319)');

    remove_tree($dir);
    remove_tree($file);
}

# see what happens if a file exists where we want a directory
SKIP: {
    my $entry = catfile($tmp_base, "file");
    skip "VMS can have a file and a directory with the same name.", 4
        if $Is_VMS;
    skip "Cannot create $entry", 4 unless open OUT, "> $entry";
    print OUT "test file, safe to delete\n", scalar(localtime), "\n";
    close OUT;
    ok(-e $entry, "file exists in place of directory");

    mkpath( $entry, {error => \$error} );
    is( scalar(@$error), 1, "caught error condition" );
    ($file, $message) = each %{$error->[0]};
    is( $entry, $file, "and the message is: $message");

    eval {@created = mkpath($entry, 0, 0700)};
    $error = $@;
    chomp $error; # just to remove silly # in TAP output
    cmp_ok( $error, 'ne', "", "no directory created (old-style) err=$error" )
        or diag(@created);
}

{
    $dir = catdir($tmp_base, 'ZZ');
    @created = mkpath($dir);
    is(scalar(@created), 1, "create a ZZ directory");

    local @ARGV = ($dir);
    rmtree( [grep -e $_, @ARGV], 0, 0 );
    ok(!-e $dir, "blow it away via \@ARGV");
}

SKIP : {
    my $skip_count = 19;
    # this test will fail on Windows, as per:
    #   http://perldoc.perl.org/perlport.html#chmod

    skip "Windows chmod test skipped", $skip_count
        if $^O eq 'MSWin32';
    my $mode;
    my $octal_mode;
    my @inputs = (
      0777, 0700, 0070, 0007,
      0333, 0300, 0030, 0003,
      0111, 0100, 0010, 0001,
      0731, 0713, 0317, 0371, 0173, 0137,
      00 );
    my $input;
    my $octal_input;
    $dir = catdir($tmp_base, 'chmod_test');

    foreach (@inputs) {
        $input = $_;
        @created = mkpath($dir, {chmod => $input});
        $mode = (stat($dir))[2];
        $octal_mode = S_IMODE($mode);
        $octal_input = sprintf "%04o", S_IMODE($input);
        is($octal_mode,$input, "create a new directory with chmod $input ($octal_input)");
        rmtree( $dir );
    }
}

my $base = catdir($tmp_base,'output');
$dir  = catdir($base,'A');
$dir2 = catdir($base,'B');

is(_run_for_verbose(sub {@created = mkpath($dir, 1)}),
    "mkdir $base\nmkdir $dir\n",
    'mkpath verbose (old style 1)'
);

is(_run_for_verbose(sub {@created = mkpath([$dir2], 1)}),
    "mkdir $dir2\n",
    'mkpath verbose (old style 2)'
);

is(_run_for_verbose(sub {$count = rmtree([$dir, $dir2], 1, 1)}),
    "rmdir $dir\nrmdir $dir2\n",
    'rmtree verbose (old style)'
);

is(_run_for_verbose(sub {@created = mkpath($dir, {verbose => 1, mask => 0750})}),
    "mkdir $dir\n",
    'mkpath verbose (new style 1)'
);

is(_run_for_verbose(sub {@created = mkpath($dir2, 1, 0771)}),
    "mkdir $dir2\n",
    'mkpath verbose (new style 2)'
);

is(_run_for_verbose(sub {$count = rmtree([$dir, $dir2], 1, 1)}),
    "rmdir $dir\nrmdir $dir2\n",
    'again: rmtree verbose (old style)'
);

is(_run_for_verbose(sub {@created = make_path( $dir, $dir2, {verbose => 1, mode => 0711});}),
    "mkdir $dir\nmkdir $dir2\n",
    'make_path verbose with final hashref'
);

is(_run_for_verbose(sub {@created = remove_tree( $dir, $dir2, {verbose => 1});}),
    "rmdir $dir\nrmdir $dir2\n",
    'remove_tree verbose with final hashref'
);

# Have to re-create these 2 directories so that next block is not skipped.
@created = make_path(
    $dir,
    $dir2,
    { mode => 0711 }
);
is(@created, 2, "2 directories created");

SKIP: {
    $file = catdir($dir2, "file");
    skip "Cannot create $file", 2 unless open OUT, "> $file";
    print OUT "test file, safe to delete\n", scalar(localtime), "\n";
    close OUT;

    ok(-e $file, "file created in directory");

    is(_run_for_verbose(sub {$count = rmtree($dir, $dir2, {verbose => 1, safe => 1})}),
        "rmdir $dir\nunlink $file\nrmdir $dir2\n",
        'rmtree safe verbose (new style)'
    );
}

{
    my $base = catdir($tmp_base,'output2');
    my $dir  = catdir($base,'A');
    my $dir2 = catdir($base,'B');

    {
        my $warn;
        $SIG{__WARN__} = sub { $warn = shift };

        my @created = make_path(
            $dir,
            $dir2,
            { mode => 0711, foo => 1, bar => 1 }
        );
        like($warn,
            qr/Unrecognized option\(s\) passed to make_path\(\):.*?bar.*?foo/,
            'make_path with final hashref warned due to unrecognized options'
        );
    }

    {
        my $warn;
        $SIG{__WARN__} = sub { $warn = shift };

        my @created = remove_tree(
            $dir,
            $dir2,
            { foo => 1, bar => 1 }
        );
        like($warn,
            qr/Unrecognized option\(s\) passed to remove_tree\(\):.*?bar.*?foo/,
            'remove_tree with final hashref failed due to unrecognized options'
        );
    }
}

SKIP: {
    my $nr_tests = 6;
    my $cwd = getcwd() or skip "failed to getcwd: $!", $nr_tests;
    rmtree($tmp_base, {result => \$list} );
    is(ref($list), 'ARRAY', "received a final list of results");          # 1
    ok( !(-d $tmp_base), "test base directory gone" );                    # 2

    my $p = getcwd();
    my $x = "x$$";
    my $xx = $x . "x";

    # setup
    ok(mkpath($xx), "make $xx");                                         # 3
    ok(chdir($xx), "... and chdir $xx");                                 # 4
    END {
#         ok(chdir($p), "... now chdir $p");
#         ok(rmtree($xx), "... and finally rmtree $xx");
       chdir($p);
       rmtree($xx);
    }

    # create and delete directory
    my $px = catdir($p, $x);
    ok(mkpath($px), 'create and delete directory 2.07');                # 5
    ok(rmtree($px), '.. rmtree fails in File-Path-2.07');               # 6
}

my $windows_dir = 'C:\Path\To\Dir';
my $expect = 'c:/path/to/dir';
is(
    File::Path::_slash_lc($windows_dir),
    $expect,
    "Windows path unixified as expected"
);

{
    my ($x, $message, $object, $expect, $rv, $arg, $error);
    my ($k, $v, $second_error, $third_error);
    local $! = 2;
    $x = $!;

    $message = 'message in a bottle';
    $object = '/path/to/glory';
    $expect = "$message for $object: $x";
    $rv = _run_for_warning( sub {
        File::Path::_error(
            {},
            $message,
            $object
        );
    } );
    like($rv, qr/^$expect/,
        "no \$arg->{error}: defined 2nd and 3rd args: got expected error message");

    $object = undef;
    $expect = "$message: $x";
    $rv = _run_for_warning( sub {
        File::Path::_error(
            {},
            $message,
            $object
        );
    } );
    like($rv, qr/^$expect/,
        "no \$arg->{error}: defined 2nd arg; undefined 3rd arg: got expected error message");

    $message = 'message in a bottle';
    $object = undef;
    $expect = "$message: $x";
    $arg = { error => \$error };
    File::Path::_error(
        $arg,
        $message,
        $object
    );
    is(ref($error->[0]), 'HASH',
        "first element of array inside \$error is hashref");
    ($k, $v) = %{$error->[0]};
    is($k, '', 'key of hash is empty string, since 3rd arg was undef');
    is($v, $expect, "value of hash is 2nd arg: $message");

    $message = '';
    $object = '/path/to/glory';
    $expect = "$message: $x";
    $arg = { error => \$second_error };
    File::Path::_error(
        $arg,
        $message,
        $object
    );
    is(ref($second_error->[0]), 'HASH',
        "first element of array inside \$second_error is hashref");
    ($k, $v) = %{$second_error->[0]};
    is($k, $object, "key of hash is '$object', since 3rd arg was defined");
    is($v, $expect, "value of hash is 2nd arg: $message");

    $message = '';
    $object = undef;
    $expect = "$message: $x";
    $arg = { error => \$third_error };
    File::Path::_error(
        $arg,
        $message,
        $object
    );
    is(ref($third_error->[0]), 'HASH',
        "first element of array inside \$third_error is hashref");
    ($k, $v) = %{$third_error->[0]};
    is($k, '', "key of hash is empty string, since 3rd arg was undef");
    is($v, $expect, "value of hash is 2nd arg: $message");
}
