package Pcore::Util::Src::Filter::md;

use Pcore -class, -res;

with qw[Pcore::Util::Src::Filter];

sub decompress ($self) {
    my $options = $self->dist_cfg->{prettier} || $self->src_cfg->{prettier};

    my $in_temp = P->file1->tempfile;
    P->file->write_bin( $in_temp, $self->{data} );

    my $proc = P->sys->run_proc(
        [ 'prettier', $in_temp, $options->@*, '--parser=markdown' ],
        use_fh => 1,
        stdout => 1,
        stderr => 1,
    )->capture;

    $self->{data}->$* = $proc->{stdout}->$*;

    return res 200;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::Src::Filter::md

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
