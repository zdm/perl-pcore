package Pcore::Core::Logger::Pipe::file;

use Pcore -class;
use Fcntl qw[:flock];

extends qw[Pcore::Core::Logger::Pipe];

has path => ( is => 'ro', isa => InstanceOf ['Pcore::Util::Path'], required => 1 );

has hid => ( is => 'lazy', isa => Str, init_arg => undef );

around new => sub ( $orig, $self, $args ) {
    if ( $args->{uri}->path->is_abs ) {
        P->file->mkpath( $args->{uri}->path->dirname );

        $args->{path} = $args->{uri}->path;
    }
    elsif ( $ENV->{LOG_DIR} ) {
        $args->{path} = P->path( $ENV->{LOG_DIR} . $args->{uri}->path );
    }
    else {
        return;
    }

    return $self->$orig($args);
};

sub _build_id ($self) {
    return 'logger_file_' . $self->path;
}

sub _build_hid ($self) {
    my $hid = $self->id;

    H->add(
        $hid      => 'File',
        path      => $self->path->to_string,
        binmode   => ':encoding(UTF-8)',
        autoflush => 1
    );

    return $hid;
}

sub sendlog ( $self, $header, $data, $tag ) {
    my $hid = $self->hid;

    my $h = H->$hid->h;

    flock $h, LOCK_EX or die;

    say {$h} $header, q[ ], $data, $LF;

    flock $h, LOCK_UN or die;

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    1 │ 1                    │ NamingConventions::Capitalization - Package "Pcore::Core::Logger::Pipe::file" does not start with a upper case │
## │      │                      │ letter                                                                                                         │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Core::Logger::Pipe::file

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
