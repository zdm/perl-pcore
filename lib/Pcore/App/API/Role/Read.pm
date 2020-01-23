package Pcore::App::API::Role::Read;

use Pcore -const, -role, -sql, -res;
use Pcore::Util::Scalar qw[is_ref];

has max_limit        => 100;
has default_limit    => ();
has default_order_by => ();

around BUILD => sub ( $orig, $self, $args ) {
    $self->$orig($args);

    $self->{default_limit} //= $self->{max_limit};

    return;
};

sub BUILD ( $self, $args ) {return}

sub _read ( $self, $total_sql, $main_sql, $args = undef ) {
    my $dbh = $self->{dbh};

    my $data;

    # get by id
    if ( exists $args->{id} ) {
        $data = $dbh->selectrow( is_ref $main_sql ? $main_sql : [ $main_sql, $args->{where} // () ] );
    }

    # get all matched rows
    else {
        my $total = $dbh->selectrow( is_ref $total_sql ? $total_sql : [ $total_sql, $args->{where} // () ] );

        # total query error
        if ( !$total ) {
            $data = $total;
        }

        # no results
        elsif ( !$total->{data}->{total} ) {
            $data = res 200,
              total   => 0,
              summary => { total => 0 };
        }

        # has results
        else {
            $data = $dbh->selectall(
                is_ref $main_sql ? $main_sql : [    #
                    $main_sql,
                    $args->{where} // (),
                    ORDER_BY $args->{order_by} // $self->{default_order_by},
                    LIMIT do {
                        if ( $args->{limit} ) {
                            if ( $self->{max_limit} && $args->{limit} > $self->{max_limit} ) {
                                $self->{max_limit};
                            }
                            else {
                                $args->{limit};
                            }
                        }
                        else {
                            $self->{default_limit};
                        }
                    },
                    OFFSET do {
                        if ( defined $args->{offset} && $args->{offset} < 0 ) {
                            undef;
                        }
                        else {
                            $args->{offset};
                        }
                    },
                ]
            );

            if ($data) {
                $data->{total}   = $total->{data}->{total};
                $data->{summary} = $total->{data};
            }
        }
    }

    return $data;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 20                   | Subroutines::ProhibitManyArgs - Too many arguments                                                             |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 20                   | Subroutines::ProhibitUnusedPrivateSubroutines - Private subroutine/method '_read' declared but not used        |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::App::API::Role::Read

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
