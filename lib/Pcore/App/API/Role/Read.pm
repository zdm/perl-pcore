package Pcore::App::API::Role::Read;

use Pcore -const, -role, -sql, -res;
use Pcore::Util::Scalar qw[is_ref];

sub _read ( $self, $main_sql, $total_sql = undef ) {
    my $dbh = $self->{dbh};

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
    my $data = $dbh->selectall($main_sql);

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
## |    3 | 6                    | Subroutines::ProhibitUnusedPrivateSubroutines - Private subroutine/method '_read' declared but not used        |
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
