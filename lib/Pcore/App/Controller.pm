package Pcore::App::Controller;

use Pcore -role;

has app  => ( required => 1 );    # ConsumerOf ['Pcore::App']
has host => ( required => 1 );    # HTTP controller host
has path => ();                   # HTTP controller url path, always finished with "/"

sub run ( $self, $req ) {
    $req->(404)->finish;

    return;
}

sub get_abs_path ( $self, $path ) {
    if ( $self->{path} eq '/' ) {
        return "/$path";
    }
    else {
        return "$self->{path}/$path";
    }
}

sub get_nginx_cfg ($self) {
    return;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::App::Controller

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
