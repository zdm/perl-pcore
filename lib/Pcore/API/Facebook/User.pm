package Pcore::API::Facebook::User;

use Pcore -role, -const;

const our $VER => 3.3;

sub me ( $self, $cb = undef ) {
    return $self->_req( 'GET', 'me', undef, undef, $cb );
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::API::Facebook::User

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
