package Pcore::Util::PM::RPC::Worker;

use Pcore -role;

sub rpc_call ( $self, @ ) {
    main->rpc_call( splice @_, 1 );

    return;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::PM::RPC::Worker

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
