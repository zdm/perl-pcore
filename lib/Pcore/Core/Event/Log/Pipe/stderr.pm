package Pcore::Core::Event::Log::Pipe::stderr;

use Pcore -class, -ansi;
use Pcore::Util::Text qw[remove_ansi];

with qw[Pcore::Core::Event::Log::Pipe];

has tmpl => ( is => 'ro', isa => InstanceOf ['Pcore::Util::Template'], init_arg => undef );
has is_ansi => ( is => 'ro', isa => Bool, init_arg => undef );

sub sendlog ( $self, $ev, $data ) {
    return if $ENV->{LOG_STDERR_DISABLED};

    # init template
    if ( !exists $self->{tmpl} ) {
        $self->{tmpl} = P->tmpl;

        my $header = $BOLD . $GREEN . '[<: $date.strftime("%Y-%m-%d %H:%M:%S.%3N") :>]' . $BOLD . $YELLOW . '[<: $package :>]' . $BOLD . $RED . '[<: $severity :>]' . $RESET;

        my $template = qq[$header <: \$title :>
: for \$body -> \$line {
    <: \$line :>
: }];

        $self->{tmpl}->cache_string_tmpl( message => \$template );
    }

    # check ansi support
    $self->{is_ansi} //= -t $STDERR_UTF8 ? 1 : 0;    ## no critic qw[InputOutput::ProhibitInteractiveTest]

    # sendlog
    {
        local $data->{date} = P->date->from_epoch( $data->{timestamp} );

        my $message = $self->{tmpl}->render( 'message', $data );

        remove_ansi $message->$* if !$self->{is_ansi};

        print {$STDERR_UTF8} $message->$*;
    }

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 20                   | ValuesAndExpressions::ProhibitImplicitNewlines - Literal line breaks in a string                               |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    2 | 33                   | Variables::ProhibitLocalVars - Variable declared as "local"                                                    |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    1 | 18                   | ValuesAndExpressions::RequireInterpolationOfMetachars - String *may* require interpolation                     |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Core::Event::Log::Pipe::stderr

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
