package Pcore::Dist::Build;

use Pcore qw[-class -const];
use Pcore::Util::File::Tree;

has dist => ( is => 'ro', isa => InstanceOf ['Pcore::Dist'] );

has user_cfg_path => ( is => 'lazy', isa => Str, init_arg => undef );
has user_cfg => ( is => 'lazy', isa => Maybe [HashRef], init_arg => undef );
has wiki => ( is => 'lazy', isa => Maybe [ InstanceOf ['Pcore::Dist::Build::Wiki'] ], init_arg => undef );

no Pcore;

const our $XT_TEST => {
    author  => [ 'AUTHOR_TESTING',    '"smoke bot" testing' ],
    release => [ 'RELEASE_TESTING',   'release candidate testing' ],
    smoke   => [ 'AUTOMATED_TESTING', '"smoke bot" testing' ],
};

sub _build_user_cfg_path ($self) {
    return $PROC->{PCORE_USER_DIR} . 'pcore.ini';
}

sub _build_user_cfg ($self) {
    return -f $self->user_cfg_path ? P->cfg->load( $self->user_cfg_path ) : undef;
}

sub _build_wiki ($self) {
    return P->class->load('Pcore::Dist::Build::Wiki')->new( { dist => $self->dist } );
}

sub create ( $self, @args ) {
    require Pcore::Dist::Build::Create;

    return Pcore::Dist::Build::Create->new( { @args, build => $self } )->run;    ## no critic qw[ValuesAndExpressions::ProhibitCommaSeparatedStatements]
}

sub setup ($self) {
    my $cfg = [
        _ => [
            author           => q[],
            email            => q[],
            license          => 'Perl_5',
            copyright_holder => q[],
        ],
        PAUSE => [
            username  => q[],
            passwword => q[],
        ],
        Bitbucket => [ username => q[], ],
        DockerHub => [ username => q[], ],
    ];

    return if -f $self->user_cfg_path && P->term->prompt( qq["@{[$self->user_cfg_path]}" already exists. Overwrite?], [qw[yes no]], enter => 1 ) eq 'no';

    P->cfg->store( $self->user_cfg_path, $cfg );

    say qq["@{[$self->user_cfg_path]}" was created, fill it manually with correct values];

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
        author  => 0,
        release => 0,
        smoke   => 0,
        all     => 0,
        jobs    => 1,
        verbose => 0,
        keep    => 0,
        @_[ 1 .. $#_ ],
    );

    local $ENV{AUTHOR_TESTING}    = 1 if $args{author}  || $args{all};
    local $ENV{RELEASE_TESTING}   = 1 if $args{release} || $args{all};
    local $ENV{AUTOMATED_TESTING} = 1 if $args{smoke}   || $args{all};

    local $ENV{HARNESS_OPTIONS} = $ENV{HARNESS_OPTIONS} ? "$ENV{HARNESS_OPTIONS}:j$args{jobs}" : "j$args{jobs}";

    my $build = $self->temp_build( $args{keep} );

    # build & test
    {
        my $chdir_guard = P->file->chdir($build);

        my $psplit = $MSWIN ? q[\\] : q[/];

        return if !P->sys->system(qw[perl Build.PL]);

        return if !P->sys->system(".${psplit}Build");

        return if !P->sys->system( ".${psplit}Build", 'test', ( $args{verbose} ? '--verbose' : q[] ) );
    }

    return 1;
}

sub release ( $self, @args ) {
    require Pcore::Dist::Build::Release;

    return Pcore::Dist::Build::Release->new( { dist => $self->dist, @args } )->run;
}

sub par ( $self, @ ) {
    my %args = (
        release => 0,
        crypt   => undef,
        upx     => undef,
        clean   => undef,
        @_[ 1 .. $#_ ],
    );

    require Pcore::Dist::Build::PAR;

    Pcore::Dist::Build::PAR->new( { %args, dist => $self->dist } )->run;    ## no critic qw[ValuesAndExpressions::ProhibitCommaSeparatedStatements]

    return;
}

sub temp_build ( $self, $keep = 0 ) {
    require Pcore::Dist::Build::Temp;

    return Pcore::Dist::Build::Temp->new( { dist => $self->dist } )->run($keep);
}

sub tgz ($self) {
    my $temp = $self->temp_build;

    require Archive::Tar;

    my $tgz = Archive::Tar->new;

    my $base_dir = $self->dist->name . q[-] . $self->dist->version . q[/];

    P->file->find(
        $temp,
        abs => 0,
        dir => 0,
        sub ($path) {
            my $mode;

            if ( $path =~ m[\A(script|t)/]sm ) {
                $mode = P->file->calc_chmod('rwxr-xr-x');
            }
            else {
                $mode = P->file->calc_chmod('rw-r--r--');
            }

            $tgz->add_data( $base_dir . $path, P->file->read_bin($path)->$*, { mode => $mode } );

            return;
        }
    );

    my $path = $PROC->{PCORE_SYS_DIR} . 'build/' . $self->dist->name . q[-] . $self->dist->version . '.tar.gz';

    $tgz->write( $path, Archive::Tar::COMPRESS_GZIP() );

    return $path;
}

1;
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
