package Pcore::Core::Logger::Pipe::file;

use Pcore -class;

extends qw[Pcore::Core::Logger::Pipe];

has path => ( is => 'lazy', isa => Str, init_arg => undef );

# TODO full path name
sub _build_id ($self) {
    return $self->uri->scheme . q[:///] . $self->path;
}

sub _build_path ($self) {
    return $ENV->{SCRIPT_DIR} . $self->uri->path;
}

sub sendlog ( $self, $header, $data, $tag ) {
    P->file->append_text( $self->path, $header, q[ ], $data, $LF );

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
