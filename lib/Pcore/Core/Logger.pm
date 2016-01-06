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

    for (@pipe) {
        my $uri = P->uri($_);

        if ( my $pipe = P->class->load( $uri->scheme, ns => 'Pcore::Core::Logger::Pipe' )->new( { uri => $uri } ) ) {
            if ( $PIPE->{ $pipe->id } ) {
                $pipe = $PIPE->{ $pipe->id };
            }
            else {
                $PIPE->{ $pipe->id } = $pipe;

                P->scalar->weaken( $PIPE->{ $pipe->id } );
            }

            $ch->add_pipe($pipe);
        }
    }

    # remove channel without pipes
    if ( !$ch->pipe->%* ) {
        delete $self->channel->{$name};

        return;
    }

    return $ch;
}

sub _AUTOLOAD ( $self, $method, @ ) {
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
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 42                   │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 51                   │ Subroutines::ProhibitUnusedPrivateSubroutines - Private subroutine/method '_AUTOLOAD' declared but not used    │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
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
