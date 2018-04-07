package <: $module_name ~ "::Util" :>;

use Pcore -class;
use <: $module_name ~ "::Const qw[:CONST]" :>;

has dbh => ( is => 'ro', isa => ConsumerOf ['Pcore::Handle::DBI'], init_arg => undef );

sub build_dbh ( $self, $db ) {
    $self->{dbh} = P->handle($db) !defined $self->{dbh};

    return $self->{dbh};
}

# TODO
sub update_schema ( $self, $db, $cb ) {
    my $dbh = $self->build_dbh($db);

    $dbh->add_schema_patch(
        1 => <<'SQL'
            CREATE TABLE IF NOT EXISTS "aaa" (
                "id" BIGSERIAL PRIMARY KEY NOT NULL
            );
SQL
    );

    $dbh->upgrade_schema($cb);

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 1, 4                 | ValuesAndExpressions::ProhibitInterpolationOfLiterals - Useless interpolation of literal string                |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    1 | 45                   | Documentation::RequirePackageMatchesPodName - Pod NAME on line 49 does not match the package declaration       |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

<: $module_name ~ "::Util" :>

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
