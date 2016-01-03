package Pcore::Util::PM::Process;

use Pcore -class;
use Config qw[%Config];
use if $MSWIN, 'Win32::Process';
use if $MSWIN, 'Win32API::File';

# TODO
# for perl process:
#     - can create additional in/out pipes for communication;
#     - can inherit / no-inherit STD;
# for foreign process:
#     - can only redirect STD handles;

# has cmd => ( is => 'ro', isa => ArrayRef, required => 1 );

has perl => ( is => 'ro', isa => Str );

has blocking => ( is => 'ro', isa => Bool, default => 0 );    # run process via "system" call
has on_ready => ( is => 'ro', isa => CodeRef );
has on_exit  => ( is => 'ro', isa => CodeRef );

has in  => ( is => 'lazy', isa => GlobRef );
has out => ( is => 'lazy', isa => GlobRef );
has err => ( is => 'lazy', isa => GlobRef );

has exit_code => ( is => 'ro', isa => PositiveOrZeroInt, default => 0, init_arg => undef );
has pid => ( is => 'ro', isa => PositiveInt, init_arg => undef );

sub BUILDARGS ( $self, @ ) {
    return { splice @_, 1 };
}

sub BUILD ( $self, $args ) {
    $self->_run_perl if $self->perl;

    return;
}

sub DEMOLISH ( $self, $global ) {
    if ($MSWIN) {
        Win32::Process::KillProcess( $self->pid, 0 ) if $self->pid;
    }
    else {
        kill 9, $self->pid or 1 if $self->pid;
    }

    return;
}

sub perl_path ($self) {
    state $perl = do {
        if ( $ENV->is_par ) {
            "$ENV{PAR_TEMP}/perl" . $MSWIN ? '.exe' : q[];
        }
        else {
            $^X;
        }
    };

    return $perl;
}

sub _run_perl ($self) {
    my @cmd;

    my $args = P->data->to_cbor(
        {   script => {
                path    => $ENV->{SCRIPT_PATH},
                version => $main::VERSION->normal,
            },
            data => 'мама',
        },
        encode => 2,
    )->$*;

    if ($MSWIN) {
        @cmd = ( $ENV{COMSPEC}, qq[/D /C @{[$self->perl_path]} -MPcore::Util::PM::Process::Wrapper -e "" $args] );
    }
    else {
        @cmd = ( $self->perl_path, '-MPcore::Util::PM::Process::Wrapper', '-e', q[], $args );
    }

    local $ENV{PERL5LIB} = join $Config{path_sep}, grep { !ref } @INC;

    if ($MSWIN) {
        Win32::Process::Create(    #
            my $process,
            @cmd,
            1,                     # inherit STD* handles
            0,                     # WARNING: not works if not 0, Win32::Process::CREATE_NO_WINDOW(),
            q[.]
        ) || die $!;

        $self->{pid} = $process->GetProcessID;
    }
    else {
        unless ( $self->{pid} = fork ) {
            exec @cmd or die;
        }
    }

    return;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::PM::Process

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
