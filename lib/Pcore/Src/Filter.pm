package Pcore::Src::Filter;

use Pcore -role;

has file      => ( required => 1 );                           # InstanceOf ['Pcore::Src::File'], weaken
has buffer    => ( required => 1 );                           # ScalarRef
has has_kolon => ( is       => 'lazy', init_arg => undef );

sub src_cfg ($self) { return Pcore::Src::File->cfg }

sub dist_cfg ($self) { return $self->{file}->dist_cfg }

sub decompress ($self) { return 0 }

sub compress ($self) { return 0 }

sub obfuscate ($self) { return 0 }

sub _build_has_kolon ($self) {
    return 1 if $self->{buffer}->$* =~ /<: /sm;

    return 1 if $self->{buffer}->$* =~ /^: /sm;

    return 0;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Src::Filter

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
