package Dist::Zilla::PluginBundle::Pcore;

use Moose;
use Pcore;
use Moose::Util::TypeConstraints;

with qw[Dist::Zilla::Role::PluginBundle::Easy Dist::Zilla::Role::PluginBundle::PluginRemover];

has builder => ( is => 'ro', isa => enum( [qw[MakeMaker MakeMaker::IncShareDir ModuleBuild ModuleBuildTiny]] ), lazy => 1, default => sub { $_[0]->payload->{builder} || 'ModuleBuildTiny' } );

no Pcore;
no Moose;

# perl CPAN distribution
# http://www.perlmonks.org/?node_id=1009586

sub build_file {
    my $self = shift;

    return $self->builder =~ /MakeMaker/sm ? 'Makefile.PL' : 'Build.PL';
}

sub configure {
    my $self = shift;

    $self->add_plugins(
        ['Pcore::PAR'],

        [   GatherDir => {
                prune_directory => [

                    # general build
                    '^blib$',

                    # Module::Build
                    '^_build$',

                    # Pcore
                    '^contrib$',
                    '^data$',
                    '^examples$',
                    '^log$',
                    '^resources$',
                    '^wiki$',
                ],
                exclude_filename => [

                    # general build
                    qw[META.json META.yml MYMETA.json MYMETA.yml LICENSE MANIFEST SIGNATURE README.md],
                    $self->build_file,

                    # Module::Build
                    qw[_build_params Build Build.bat],

                    # MakeMaker
                    qw[Makefile pm_to_blib],

                    # Pcore
                    qw[logo.png],

                    # Docker
                    qw[Dockerfile],
                ],
            }
        ],

        # prune stuff that you probably don't mean to include
        ['PruneCruft'],

        # make the working copy installable
        [   CopyFilesFromBuild => {
                copy => [    #
                    'LICENSE',
                    'README.md',
                    'META.json',
                    $self->build_file,
                ]
            }
        ],

        # extract distribution version from main module
        ['VersionFromModule'],

        # create README.md from main module POD
        [ ReadmeFromPod => { type => 'markdown' } ],

        # load prereqs from cpanfile
        ['Prereqs::FromCPANfile'],

        # set no_index to sensible directories
        [   MetaNoIndex => {
                directory => [    #
                    'inc',
                    'share',
                    't',
                    'xt',
                ]
            }
        ],

        # automatically fill meta.resources with data from bitbucket repo
        ['Pcore::Meta'],

        # create META.json
        ['MetaJSON'],

        # create xt/release/pod-syntax.t
        ['PodSyntaxTests'],

        # create LICENSE
        ['License'],

        # rewrite ./xt tests to ./t tests with skips
        ['ExtraTests'],

        [ ExecDir => { dir => 'script' } ],

        ['ShareDir'],

        # create MANIFEST
        ['Manifest'],

        # prune files, listed in MANIFEST.SKIP, from build
        ['ManifestSkip'],

        # main builder plugin
        [ $self->builder ],

        # prune files from build
        [   PruneFiles => {
                filename => [    #
                    'MANIFEST.SKIP',
                ]
            }
        ],

        # create SIGNATURE
        # NOTE need to set $ENV{MODULE_SIGNATURE_AUTHOR} = q["<author-email>"];
        # [ 'Signature' => { sign => 'always' } ],

        # release
        ['TestRelease'],
        ['ConfirmRelease'],
        ['Pcore::UploadToCPAN'],
    );

    return;
}

__PACKAGE__->meta->make_immutable;

1;

__END__
=pod

=encoding utf8

=head1 NAME

Dist::Zilla::PluginBundle::Pcore

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
