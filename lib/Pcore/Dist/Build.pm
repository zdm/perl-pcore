package Pcore::Dist::Build;

use Pcore qw[-class];

has dist => ( is => 'ro', isa => InstanceOf ['Pcore::Dist'], required => 1 );

has wiki => ( is => 'lazy', isa => Maybe [ InstanceOf ['Pcore::Dist::Build::Wiki'] ], init_arg => undef );

no Pcore;

our $CLEAN = {
    dir => [

        # general build
        'blib',

        # Module::Build
        '_build',
    ],
    file => [

        # general build
        qw[META.yml MYMETA.json MYMETA.yml],

        # Module::Build
        qw[_build_params Build Build.bat],

        # MakeMaker
        qw[Makefile pm_to_blib],
    ],
};

sub _build_wiki ($self) {
    return P->class->load('Pcore::Dist::Build::Wiki')->new( { dist => $self->dist } );
}

sub clean ($self) {
    for my $dir ( $CLEAN->{dir}->@* ) {
        P->file->rmtree($dir);
    }

    for my $file ( $CLEAN->{file}->@* ) {
        unlink $file or die qq[Can't unlink "$file"] if -f $file;
    }

    return;
}

sub update ($self) {
    require Pcore::Dist::Build::Update;

    Pcore::Dist::Build::Update->new( { dist => $self->dist } )->run;

    return;
}

sub deploy ( $self, %args ) {
    require Pcore::Dist::Build::Deploy;

    Pcore::Dist::Build::Deploy->new( { dist => $self->dist, %args } )->run;

    return;
}

sub test ( $self, @ ) {
    my %args = (
        release => 0,
        author  => 0,
        smoke   => 0,
        @_[ 1 .. $#_ ]
    );

    return;
}

sub release ( $self, $release_type ) {
    return;
}

sub par ( $self, @ ) {
    my %args = (
        release => 0,
        crypt   => undef,
        upx     => undef,
        clean   => undef,
        @_[ 1 .. $#_ ]
    );

    require Pcore::Dist::Build::PAR;

    Pcore::Dist::Build::PAR->new( { dist => $self->dist, %args } )->run;

    return;
}

sub temp_build ($self) {

    # TODO
    # copy files to the temp dir;
    # copy and rename xt/tests according to tests mode;
    # generate MANIFEST;
    # return temp dir;

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    1 │ 66, 81               │ CodeLayout::RequireTrailingCommas - List declaration without trailing comma                                    │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Dist::Build

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
