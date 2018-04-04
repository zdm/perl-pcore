package Pcore::App::Controller::Index;

use Pcore -role;
use Pcore::Share::WWW;

with qw[Pcore::App::Controller];

around run => sub ( $orig, $self, $req ) {
    if ( $req->{path_tail}->is_file ) {
        $self->return_static($req);

        return;
    }
    else {
        return $self->$orig($req);
    }
};

sub get_nginx_cfg ($self) {
    my @sl;

    my $last;

    # add_header    Cache-Control "public, private, must-revalidate, proxy-revalidate";

    for my $static ( reverse $ENV->share->get_storage('www')->@* ) {
        if ( !defined $last ) {
            unshift @sl, qq[
location \@$static {
    add_header    Cache-Control "public, max-age=30672000";
    root          $static;
    try_files     \$uri =404;
}];
        }
        else {
            unshift @sl, qq[
location \@$static {
    add_header    Cache-Control "public, max-age=30672000";
    root          $static;
    try_files     \@$last =404;
}];
        }

        $last = $static;
    }

    return q[
location =/ {
    error_page 418 = @backend;
    return 418;
}

location / {
    error_page 418 = @backend;
    return 418;
}] . $LF . join $LF, @sl;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 22                   | NamingConventions::ProhibitAmbiguousNames - Ambiguously named variable "last"                                  |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 28, 36, 47           | ValuesAndExpressions::ProhibitImplicitNewlines - Literal line breaks in a string                               |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    1 | 47                   | ValuesAndExpressions::RequireInterpolationOfMetachars - String *may* require interpolation                     |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::App::Controller::Index

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
