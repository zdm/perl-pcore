package Pcore::Core::Logger;

use Pcore -class, -autoload;
use Pcore::Core::Logger::Channel;

has channel => ( is => 'lazy', isa => HashRef, default => sub { {} }, init_arg => undef );

our $PIPE = {};    # weak refs, pipes are global

sub add_channel ( $self, $name, @ ) {
    my $ch;

    my $args = { name => $name };

    my @pipe;

    if ( ref $_[2] eq 'HASH' ) {
        $args->@{ keys $_[2]->%* } = values $_[2]->%*;

        @pipe = splice @_, 3;
    }
    else {
        @pipe = splice @_, 2;
    }

    if ( $self->channel->{$name} ) {
        $ch = $self->channel->{$name};
    }
    else {
        $ch = Pcore::Core::Logger::Channel->new($args);

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

sub canlog ( $self, $ch ) {
    return $self->{channel}->{$ch} ? 1 : 0;
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
## │    3 │ 18, 55               │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 68                   │ Subroutines::ProhibitUnusedPrivateSubroutines - Private subroutine/method '_AUTOLOAD' declared but not used    │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Core::Logger

=head1 SYNOPSIS

    P->log->add_channel( $channel_name, $pipe_uri, ... );

    P->log->$channel_name( $data, %tags ) if P->log->canlog($channel_name);

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
