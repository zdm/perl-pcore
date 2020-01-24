package Pcore::App::API::Role::Read;

use Pcore -const, -role, -sql, -res;
use Pcore::Util::Scalar qw[is_ref];

has max_limit        => 100;
has default_limit    => 0;
has default_order_by => undef;

sub _read ( $self, $total_sql, $main_sql, $arg = undef ) {
    my $dbh = $self->{dbh};

    # get by id
    return $dbh->selectrow($main_sql) if $args->{id};

    my $total;

    if ($total_sql) {
        $total = $dbh->selectrow($total_sql);

        # total query error
        if ( !$total ) {
            return $total;
        }

        # no results
        elsif ( !$total->{data}->{total} ) {
            return res 200,
              total   => 0,
              summary => { total => 0 };
        }
    }

    # has results
    my $data = $dbh->selectall( [
        $main_sql->@*,
        ORDER_BY( $args->{order_by} || $self->{default_order_by} ),
        LIMIT( $args->{limit}, max => $self->{max_limit}, default => $self->{default_limit} ),
        OFFSET( $args->{offset} );
    ] );

    if ( $data && $total ) {
        $data->{total}   = $total->{data}->{total};
        $data->{summary} = $total->{data};
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
## |    3 | 10                   | Subroutines::ProhibitManyArgs - Too many arguments                                                             |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 10                   | Subroutines::ProhibitUnusedPrivateSubroutines - Private subroutine/method '_read' declared but not used        |
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
