package Pcore::CDN;

use Pcore -class;
use overload '&{}' => sub ( $self, @ ) {
    sub { $self->{bucket}->{ $self->{default} }->get_url(@_) }
  },
  fallback => 1;

has bucket => ( init_arg => undef );
has default => ();

around new => sub ( $orig, $self, $args ) {
    $self = $self->$orig;

    $self->{default} = delete $args->{default};

    while ( my ( $name, $cfg ) = each $args->%* ) {
        $self->{bucket}->{$name} = P->class->load( $cfg->{type}, ns => 'Pcore::CDN::Bucket' )->new($cfg);

        $self->{default} //= $name;
    }

    return $self;
};

sub get_nginx_cfg($self) {
    my @buf;

    for my $buck ( $self->{bucket}->%* ) {
        next if !$buck->{is_local};

        push @buf, $buck->get_nginx_cfg;
    }

    return join $LF, @buf;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::CDN

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
