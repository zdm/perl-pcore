package Pcore::Core::CLI::Cmd;

use Pcore -role;

# COMMON
sub cli_class ($self) {
    return;
}

sub cli_abstract ($self) {
    return;
}

sub cli_help ($self) {
    return;
}

# CMD ROUTER
sub cli_cmd ($self) {
    return;
}

# CMD
sub cli_name ($self) {
    return;
}

sub cli_opt ($self) {
    return;
}

sub cli_arg ($self) {
    return;
}

# return error message or undef
sub cli_validate ( $self, $opt, $arg, $rest ) {
    return;
}

sub cli_run ( $self, $opt, $arg, $rest ) {
    return;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Core::CLI::Cmd

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
