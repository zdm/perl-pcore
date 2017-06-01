package Pcore::Core::Event::Listener::Pipe::file;

use Pcore -class, -ansi;
use Pcore::Util::Text qw[remove_ansi];
use Fcntl qw[:flock];
use IO::File;

with qw[Pcore::Core::Event::Listener::Pipe];

has header => ( is => 'ro', isa => Str, default => '[<: $date.strftime("%Y-%m-%d %H:%M:%S.%4N") :>][<: $channel :>][<: $level :>]' );

has _tmpl => ( is => 'ro', isa => InstanceOf ['Pcore::Util::Template'], init_arg => undef );
has _path => ( is => 'ro', isa => InstanceOf ['Pcore::Util::Path'],     init_arg => undef );
has _h    => ( is => 'ro', isa => InstanceOf ['IO::File'],              init_arg => undef );

has _init => ( is => 'ro', isa => Bool, init_arg => undef );

sub sendlog ( $self, $ev, $data ) {

    # init
    if ( !$self->{_init} ) {
        $self->{_init} = 1;

        # init template
        $self->{_tmpl} = P->tmpl;

        my $template = qq[$self->{header} <: \$title | raw :>
: if \$body {
<: \$body | raw :>
: }];

        $self->{_tmpl}->cache_string_tmpl( message => \$template );

        # init path
        if ( $self->{uri}->path->is_abs ) {
            P->file->mkpath( $self->{uri}->path->dirname );

            $self->{_path} = $self->{uri}->path;
        }
        else {
            $self->{_path} = P->path( $ENV->{DATA_DIR} . $self->{uri}->path );
        }
    }

    # open filehandle
    if ( !-f $self->{_path} || !$self->{_h} ) {
        $self->{_h} = IO::File->new( $self->{path}, '>>', P->file->calc_chmod(q[rw-------]) ) or die qq[Unable to open "$self->{path}"];

        $self->{_h}->binmode(':encoding(UTF-8)');

        $self->{_h}->autoflush(1);
    }

    # sendlog
    {
        local $data->{date} = P->date->from_epoch( $data->{timestamp} );

        # indent body
        local $data->{body} = $data->{body} =~ s/^/    /smgr if $data->{body};

        my $message = $self->{_tmpl}->render( 'message', $data );

        remove_ansi $message->$*;

        flock $self->{_h}, LOCK_EX or die;

        print { $self->{_h} } $message->$*;

        flock $self->{_h}, LOCK_UN or die;
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
## |    3 | 27                   | ValuesAndExpressions::ProhibitImplicitNewlines - Literal line breaks in a string                               |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    2 | 56, 59               | Variables::ProhibitLocalVars - Variable declared as "local"                                                    |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    1 | 10                   | ValuesAndExpressions::RequireInterpolationOfMetachars - String *may* require interpolation                     |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Core::Event::Listener::Pipe::file

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
