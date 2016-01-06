package Pcore::Core::Logger::Pipe::stderr;

use Pcore -class;

extends qw[Pcore::Core::Logger::Pipe];

sub _build_id ($self) {
    return $self->uri->scheme;
}

sub _build_is_text_ansi ($self) {
    return -t $STDERR_UTF8 ? 1 : 0;    ## no critic qw[InputOutput::ProhibitInteractiveTest]
}

sub sendlog ( $self, $header, $data, $tag ) {
    say {$STDERR_UTF8} $header . q[ ] . $data . $LF;

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    1 │ 1                    │ NamingConventions::Capitalization - Package "Pcore::Core::Logger::Pipe::stderr" does not start with a upper    │
## │      │                      │ case letter                                                                                                    │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Core::Logger::Pipe::stderr

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
