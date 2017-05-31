#!/usr/bin/env perl

package main v0.1.0;

use Pcore;
use DateTime;

# say var_types();
run();

# say objects();
# say seen_vars();
# say tied_vars();

sub run {
    my $obj1 = DateTime->now;
    my $obj2 = AA->new;
    my $obj3 = AA->new( { "1\n2" => $obj2 } );

    open my $fh1, q[>>:unix], $ENV->{TEMP_DIR} . 'p_core_dump.test' or die;    ## no critic qw[InputOutput::RequireBriefOpen]

    my $data = {
        undef                      => undef,
        qq[key_with\n\n\n_escapes] => qq[sca\nlar-русский],
        array                      => [ 1 .. 12 ],
        hash                       => {
            aa => $obj1,
            bb => 2,
        },
        datetime1 => \$obj1,
        'obj"2'   => $obj2,
        obj3      => \$obj3,
        code      => sub { },
        fh1       => $fh1,
        vstring   => \\\v1.2.3,
        regexp    => qr/^as\nма\\d$/sm,
        lvalue    => \substr( q[lvalue scalar], 0, 13 ),
        io        => *STDOUT{IO},
    };

    P->scalar->weaken( $data->{obj3} );

    say dump $data;

    close $fh1 or die;

    return;
}

sub var_types {
    _header('Different variables types:');

    open my $fh1, q[>>:unix], $ENV->{TEMP_DIR} . 'p_core_dump.test' or die;
    close $fh1 or die;

    my $data = {
        UNDEF                      => undef,
        qq[key with\n\n\n escapes] => qq[sca\nlar-русский],
        ARRAY                      => [ 1 .. 12 ],
        CODE                       => sub { },
        VSTRING                    => v1.2.3,
        REGEXP                     => qr/^as\nма\\d$/sm,
        LVALUE                     => \substr( q[lvalue scalar], 0, 13 ),
        IO                         => *STDOUT{IO},
        GLOB                       => *STDIN,
        FH1                        => $fh1,
    };

    say dump $data;

    return;
}

sub objects {
    _header('Objects:');

    my $data = {
        DateTime          => DateTime->now,
        'File::Temp'      => P->file->tempfile,
        'File::Temp::Dir' => P->file->tempdir,
    };

    say dump $data;

    return;
}

sub seen_vars {
    _header('Seen variables:');

    my $scalar = 'abc';
    my $obj1   = AA->new();
    my $obj2   = AA->new( { seen => { seen => $obj1 } } );
    my $data   = {

        # scalar
        scalar1  => \\$scalar,
        scalar2  => \$scalar,
        scalar10 => 'abcdef',

        # objects
        obj1 => { obj1 => $obj1 },
        obj2 => $obj2,
        obj3 => \$obj1,
    };
    $data->{scalar3}  = \$data->{scalar2};
    $data->{scalar11} = \$data->{scalar10};

    say dump $data, dump_method => undef;

    return;
}

sub tied_vars {
    _header('Tied variables:');

    {
        require Tie::Scalar;
        tie my $t, 'Tie::StdScalar';
        say dump $t;
    }

    {
        require Tie::Array;
        tie my @t, 'Tie::StdArray';
        say dump \@t;
    }

    {
        require Tie::Hash;
        tie my %t, 'Tie::StdHash';
        say dump \%t;
    }

    {
        require Tie::StdHandle;
        tie *FH_TIED, 'Tie::StdHandle';
        say dump *FH_TIED;
    }

    return;
}

sub _header {
    say q[-] x 30, shift;

    return;
}

package AA;

use parent qw[Exporter];

sub new {
    my $self = shift;
    my $attrs = shift // { "1\n2" => 1 };

    return bless $attrs, $self;
}

sub TO_DUMP {
    my $self   = shift;
    my $dumper = shift;
    my %args   = (
        path => undef,
        @_,
    );

    return q["TO_DUMP" method call];
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    2 | 119, 125, 131, 137   | Miscellanea::ProhibitTies - Tied variable used                                                                 |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=cut
