package Pcore::Core::Logger::Channel;

use Pcore -class;
use Term::ANSIColor qw[:constants];

has name   => ( is => 'ro', isa => Str, required => 1 );
has header => ( is => 'ro', isa => Str, default  => BOLD GREEN . '[<: $date.strftime("%H:%M:%S.%6N") :>]' . BOLD CYAN . '[<: $pid :>]' . BOLD YELLOW . '[<: $ns :>]' . BOLD RED . '[<: $channel :>]' . RESET );

has pipe => ( is => 'ro', isa => HashRef, default => sub { {} }, init_arg => undef );

has _def_tag => ( is => 'lazy', isa => HashRef, init_arg => undef );
has _header_tmpl => ( is => 'ro', isa => HashRef, default => sub { {} }, init_arg => undef );

sub _build__def_tag ($self) {
    return {
        channel     => uc $self->name,
        script_name => $ENV->{SCRIPT_NAME},
        script_dir  => $ENV->{SCRIPT_DIR},
        script_path => $ENV->{SCRIPT_PATH},
    };
}

sub addpipe ( $self, $pipe ) {
    $self->pipe->{ $pipe->id } = $pipe;

    return;
}

sub sendlog ( $self, $logger, $data, @ ) {
    my @caller = caller 1;

    # collect tags
    my $tag = {
        ns         => $caller[0],
        package    => $caller[0],
        filename   => $caller[1],
        line       => $caller[2],
        subroutine => $caller[3],
        splice( @_, 3 ),
        $self->_def_tag->%*,
        pid  => $$,
        date => P->date->now,
    };

    my $header_cache = {};

    my $data_cache = {};

    for my $pipe ( sort { $a->priority <=> $b->priority } values $self->{pipe}->%* ) {
        my $err = $@;

        my $data_type = $pipe->data_type;

        if ( !exists $self->{_header_tmpl}->{$data_type} ) {
            $self->{_header_tmpl}->{$data_type} = P->tmpl;

            $self->{_header_tmpl}->{$data_type}->cache_string_tmpl( header => \$pipe->prepare_data( $self->header ) );
        }

        # prepare and cache header
        if ( !exists $header_cache->{$data_type} ) {
            $header_cache->{$data_type} = $self->{_header_tmpl}->{$data_type}->render( 'header', $tag );
        }

        # prepare and cache data
        $data_cache->{$data_type} = $pipe->prepare_data($data) if !exists $data_cache->{$data_type};

        eval {
            # TODO
            local $@;

            local $SIG{__DIE__} = sub { };

            local $SIG{__WARN__} = sub { };

            $pipe->sendlog( $header_cache->{$data_type}->$*, $data_cache->{$data_type}, $tag );
        };

        $@ = $err;    ## no critic qw[Variables::RequireLocalizedPunctuationVars]
    }

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 40, 49               │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 68                   │ ErrorHandling::RequireCheckingReturnValueOfEval - Return value of eval not tested                              │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 70                   │ Variables::RequireInitializationForLocalVars - "local" variable not initialized                                │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    1 │ 7                    │ ValuesAndExpressions::RequireInterpolationOfMetachars - String *may* require interpolation                     │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Core::Logger::Channel

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
