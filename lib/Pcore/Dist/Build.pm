package Pcore::Dist::Build;

use Pcore qw[-class -const];
use Pcore::Util::File::Tree;

has dist => ( is => 'ro', isa => InstanceOf ['Pcore::Dist'], required => 1 );

has wiki => ( is => 'lazy', isa => Maybe [ InstanceOf ['Pcore::Dist::Build::Wiki'] ], init_arg => undef );

no Pcore;

const our $XT_TEST => {
    author  => [ 'AUTHOR_TESTING',    '"smoke bot" testing' ],
    release => [ 'RELEASE_TESTING',   'release candidate testing' ],
    smoke   => [ 'AUTOMATED_TESTING', '"smoke bot" testing' ],
};

const our $CLEAN => {
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

    Pcore::Dist::Build::PAR->new( { dist => $self->dist, %args } )->run;

    return;
}

sub temp_build ( $self, $keep = 0 ) {
    $self->update;

    my $tree = Pcore::Util::File::Tree->new;

    my $cpan_bin = $self->dist->cfg->{dist}->{cpan} && $self->dist->cfg->{dist}->{cpan_bin};

    my @dir = qw[lib/ share/ t/ xt/];

    push @dir, 'bin/' if $cpan_bin;

    for (@dir) {
        next if !-d $self->dist->root . $_;

        $tree->add_dir( $self->dist->root . $_, $_ );
    }

    for (qw[CHANGES cpanfile LICENSE META.json README.md Build.PL]) {
        $tree->add_file( $_, $self->dist->root . $_ );
    }

    # add revision.txt
    $tree->add_file( 'share/revision.txt', \$self->dist->revision );

    # add t/author-pod-syntax.t
    $tree->add_file(
        't/author-pod-syntax.t', \<<'PERL'
#!perl

# This file was generated automatically.

use strict;
use warnings;
use Test::More;
use Test::Pod 1.41;

all_pod_files_ok();
PERL
    );

    $tree->find_file(
        sub ($file) {
            if ( $cpan_bin && $file->path =~ m[\Abin/(.+)\z]sm ) {
                my $name = $1;

                if ( $file->path !~ m[[.].+\z]sm ) {    # no extension
                    $file->move( 'script/' . $name );
                }
                elsif ( $file->path =~ m[[.](?:pl|sh|cmd|bat)\z]sm ) {    # allowed extensions
                    $file->move( 'script/' . $name );
                }
                else {
                    $file->remove;
                }
            }
            elsif ( $file->path =~ m[\At/(.+)\z]sm && $file->path !~ m[[.]t\z]sm ) {
                $file->remove;
            }
            elsif ( $file->path =~ m[\Axt/(author|release|smoke)/(.+)\z]sm ) {
                my $test = $1;

                my $name = $2;

                if ( $file->path =~ m[[.]t\z]sm ) {
                    $file->move("t/$test-$name");

                    $self->_patch_xt( $file, $test );
                }
                else {
                    $file->remove;
                }
            }

            return;
        }
    );

    # remove /bin, /xt
    $tree->find_file(
        sub ($file) {
            $file->remove if $file->path =~ m[\A(?:bin|xt)/]sm;

            return;
        }
    );

    if ($keep) {
        my $path = P->file->temppath( base => $PROC->{SYS_TEMP_DIR} . '.pcore/build/', tmpl => $self->dist->name . '-XXXXXXXX' );

        $tree->write_to( $path, manifest => 1 );

        return $path;
    }
    else {
        return $tree->write_to_temp( base => $PROC->{SYS_TEMP_DIR} . '.pcore/build/', tmpl => $self->dist->name . '-XXXXXXXX', manifest => 1 );
    }
}

sub _patch_xt ( $self, $file, $test ) {
    my $content = $file->content;

    my $patch = <<"PERL";
BEGIN {
    unless ( \$ENV{$XT_TEST->{$test}->[0]} ) {
        require Test::More;

        Test::More::plan( skip_all => 'these tests are for $XT_TEST->{$test}->[1]' );
    }
}
PERL

    $content->$* =~ s/^use\s/$patch\nuse /sm;

    return;
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

    my $path = $PROC->{SYS_TEMP_DIR} . '.pcore/build/' . $self->dist->name . q[-] . $self->dist->version . '.tar.gz';

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
