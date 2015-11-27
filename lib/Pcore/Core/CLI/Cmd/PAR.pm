package Pcore::Core::CLI::Cmd::PAR;

use Pcore qw[-role];

around cli_opt => sub ( $orig, $self ) {
    my $opt = $self->$orig // {};

    if ( !$Pcore::IS_PAR ) {
        $opt->{scan_deps} = {
            short => undef,
            desc  => 'scan PAR dependencies',
        };
    }

    return $opt;
};

around cli_run => sub ( $orig, $self, $opt, @args ) {

    # scan PAR deps
    if ( $opt->{scan_deps} ) {
        require Pcore::Devel::ScanDeps;
    }

    return $self->$orig( $opt, @args );
};

no Pcore;

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Core::CLI::Cmd::PAR

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
