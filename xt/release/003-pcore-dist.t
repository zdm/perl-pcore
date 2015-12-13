#!/usr/bin/env perl

package main v0.1.0;

use Pcore;
use Test::More;
use Pcore::Util::File::Tree;

our $TESTS = 3;

plan tests => $TESTS;

# find dist by path
run_test(
    dist_share_dir => 1,
    cpan_lib       => 'blib/lib',
    cpan_share_dir => 1,
    sub ($t) {
        my $dist = Pcore::Dist->new( $t->{dist_root} );

        ok( $dist->root eq $t->{dist_root}, $t->{test_id} . '_dist_root' );

        ok( $dist->share_dir eq $t->{dist_share_dir}, $t->{test_id} . '_dist_share_dir' );

        ok( !$dist->is_installed, $t->{test_id} . '_dist_is_installed' );

        return;
    }
);

# find dist by path
run_test(
    dist_share_dir => 1,
    cpan_lib       => 'blib/lib',
    cpan_share_dir => 1,
    sub ($t) {
        my $dist = Pcore::Dist->new( $t->{cpan_lib} );

        ok( $dist->root eq $t->{dist_root}, $t->{test_id} . '_dist_root' );

        ok( $dist->share_dir eq $t->{dist_share_dir}, $t->{test_id} . '_dist_share_dir' );

        ok( !$dist->is_installed, $t->{test_id} . '_dist_is_installed' );

        return;
    }
);

# find dist by path, dist not found
run_test(
    dist_share_dir => 0,
    cpan_lib       => 'blib/lib',
    cpan_share_dir => 1,
    sub ($t) {
        ok( !defined Pcore::Dist->new( $t->{dist_root} ), $t->{test_id} . '_dist_not_found_1' );

        ok( !defined Pcore::Dist->new( $t->{cpan_lib} ), $t->{test_id} . '_dist_not_found_2' );

        return;
    }
);

done_testing $TESTS;

sub run_test (@args) {
    my $test = pop @args;

    state $i = 0;

    my $dist_name = 'Pcore-Test-DistXXX' . ++$i;

    my %args = (
        dist_share_dir => 1,        # generate /dist_root/share/dist.perl
        cpan_lib       => undef,    # generate CPAN lib
        cpan_share_dir => 0,        # make CPAM lib dist
        @args,
    );

    my $t = generate_test_dir( $dist_name, \%args );

    $t->{test_id} = $i;

    my $temp = delete $t->{temp};

    my @old_inc = @INC;

    unshift @INC, $t->{dist_lib};

    unshift @INC, $t->{cpan_lib} if $t->{cpan_lib};

    $test->($t);

    @INC = @old_inc;    ## no critic qw[Variables::RequireLocalizedPunctuationVars]

    return;
}

sub generate_test_dir ( $dist_name, $args ) {
    my $res = {
        dist_name        => $dist_name,
        package_name     => $dist_name =~ s[-][::]smgr,
        module_name      => $dist_name =~ s[-][/]smgr . '.pm',
        dist_root        => undef,
        dist_lib         => undef,
        dist_module_path => undef,
        dist_share_dir   => undef,
        cpan_lib         => undef,
        cpan_module_path => undef,
        cpan_share_dir   => undef,
    };

    my $tree = Pcore::Util::File::Tree->new;

    my $dist_perl = <<"PERL";
{   dist => {
        name => '$dist_name',
    }
}
PERL

    my $package = <<"PERL";
package $res->{package_name} v0.1.0;

1;
PERL

    # create dist root
    $tree->add_file( "lib/$res->{module_name}", \$package );

    $tree->add_file( 'share/dist.perl', \$dist_perl ) if $args->{dist_share_dir};

    # create cpan lib
    if ( $args->{cpan_lib} ) {
        $tree->add_file( "$args->{cpan_lib}/$res->{module_name}", \$package );

        $tree->add_file( "$args->{cpan_lib}/auto/share/dist/$dist_name/dist.perl", \$dist_perl ) if $args->{cpan_share_dir};
    }

    $res->{temp} = $tree->write_to_temp;

    $res->{dist_root} = $res->{temp}->path;

    $res->{dist_lib} = P->path( "$res->{dist_root}/lib/", is_dir => 1 )->to_string;

    $res->{dist_module_path} = P->path("$res->{dist_root}/lib/$res->{module_name}")->to_string;

    $res->{dist_share_dir} = P->path( "$res->{dist_root}/share/", is_dir => 1 )->to_string if $args->{dist_share_dir};

    $res->{cpan_lib} = P->path( "$res->{dist_root}/$args->{cpan_lib}", is_dir => 1 )->to_string if $args->{cpan_lib};

    $res->{cpan_module_path} = P->path("$res->{dist_root}/$args->{cpan_lib}/$res->{module_name}")->to_string if $args->{cpan_lib};

    $res->{cpan_share_dir} = P->path( "$res->{dist_root}/$args->{cpan_lib}/auto/share/dist/$dist_name/", is_dir => 1 )->to_string if $args->{cpan_share_dir};

    return $res;
}

1;
__END__
=pod

=encoding utf8

=cut
