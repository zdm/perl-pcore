package Pcore::Core::Logger;

use Pcore -class, -autoload;
use Pcore::Core::Logger::Channel;

has channel => ( is => 'lazy', isa => HashRef, default => sub { {} }, init_arg => undef );

our $PIPE = {};    # weak refs, pipes are global

sub add_channel ( $self, $name, @pipe ) {
    my $ch;

    if ( $self->channel->{$name} ) {
        $ch = $self->channel->{$name};
    }
    else {
        $ch = Pcore::Core::Logger::Channel->new( { name => $name } );

        $self->channel->{$name} = $ch;

        P->scalar->weaken( $self->channel->{$name} ) if defined wantarray;
    }

    for my $pipe (@pipe) {
        my $uri = P->uri($pipe);

        my $obj = P->class->load( $uri->scheme, ns => 'Pcore::Core::Logger::Pipe' )->new($uri);

        if ( $PIPE->{ $obj->id } ) {
            $obj = $PIPE->{ $obj->id };
        }
        else {
            $PIPE->{ $obj->id } = $obj;

            P->scalar->weaken( $PIPE->{ $obj->id } );
        }

        $ch->addpipe($obj);
    }

    return $ch;
}

sub autoload ( $self, $method, @ ) {
    my $sub = <<"PERL";
        sub ( \$self, \$data, @ ) {
            return if !\$self->{channel}->{q[$method]};

            \$self->{channel}->{q[$method]}->sendlog(\@_);

            return;
        };
PERL

    return $sub;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Core::Logger

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
