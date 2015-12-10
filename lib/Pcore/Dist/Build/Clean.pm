package Pcore::Dist::Build::Clean;

use Pcore qw[-class -const];

has dist => ( is => 'ro', isa => InstanceOf ['Pcore::Dist'], required => 1 );

no Pcore;

const our $CLEAN => {
    dir => [

        # general build
        'blib',

        # Module::Build
        '_build',
    ],
    file => [

        # general build
        qw[META.json META.yml MYMETA.json MYMETA.yml],

        # Module::Build
        qw[_build_params Build.PL Build Build.bat],

        # MakeMaker
        qw[Makefile pm_to_blib],
    ],
};

sub run ($self) {
    for my $dir ( $CLEAN->{dir}->@* ) {
        P->file->rmtree( $self->dist->root . $dir );
    }

    for my $file ( $CLEAN->{file}->@* ) {
        unlink $self->dist->root . $file or die qq[Can't unlink "$file"] if -f $self->dist->root . $file;
    }

    return;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Dist::Build::Clean - clean dist root dir

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
