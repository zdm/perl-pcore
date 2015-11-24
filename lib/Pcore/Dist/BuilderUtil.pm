package Pcore::Dist::BuilderUtil;

use Pcore qw[-role];

no Pcore;

sub _update_dist ($self) {
    my $main_module = P->file->read_bin( 'lib/' . $self->dist->main_module_rel_path );

    # generate README.md
    {
        require Pod::Markdown;

        my $parser = Pod::Markdown->new(

            # perldoc_url_prefix       => $base_url,
            perldoc_fragment_format  => 'pod_simple_html',    # CodeRef ( $self, $text )
            markdown_fragment_format => 'pod_simple_html',    # CodeRef ( $self, $text )
            include_meta_tags        => 0,
        );

        my $markdown;

        $parser->output_string( \$markdown );

        # generate markdown document
        $parser->parse_string_document( $main_module->$* );

        P->file->write_bin( 'README.md', $markdown );
    }

    # generate LICENSE
    my $lic = P->class->load( $self->dist->cfg->{dist}->{license}, ns => 'Software::License' )->new(
        {   holder => $self->dist->cfg->{dist}->{copyright_holder} || $self->dist->cfg->{dist}->{author},
            year => P->date->now->year,
        }
    );

    P->file->write_bin( 'LICENSE', $lic->fulltext );

    my $cpanfile = P->class->load('Module::CPANfile')->load('cpanfile');

    my $prereqs = $cpanfile->prereqs;

    my $mbt_version = q[ ] . P->class->load('Module::Metadata')->new_from_module('Module::Build::Tiny')->version->stringify;

    # generate Build.PL
    {
        my $reqs = $prereqs->merged_requirements( [qw/configure build test runtime/], ['requires'] );

        my $min_perl = $reqs->requirements_for_module('perl') || '5.006';

        my $template = <<"BUILD_PL";
use strict;
use warnings;

use $min_perl;
use Module::Build::Tiny$mbt_version;
Build_PL();
BUILD_PL

        P->file->write_bin( 'Build.PL', $template );
    }

    # generate META.json
    {
        my $meta = {
            abstract => q[],
            author   => [      #
                $self->dist->cfg->{dist}->{author},
            ],
            dynamic_config => 0,
            license        => [ lc $self->dist->cfg->{dist}->{license} ],
            name           => $self->dist->cfg->{dist}->{name},
            no_index       => {                                             #
                directory => [qw[inc share t xt]],
            },
            release_status => 'stable',
            resources      => {
                homepage   => q[],
                repository => {
                    web  => q[],
                    url  => q[],
                    type => q[],
                },
                bugtracker => {                                             #
                    web => q[],
                }
            },
            version => q[],
        };

        # parse version from main module
        if ( $main_module->$* =~ m[^\s*package\s+\w[\w\:\']*\s+(v?[0-9._]+)\s*;]sm ) {
            $meta->{version} = $1;
        }

        # parse abstract from main module POD
        my $class = $self->dist->cfg->{dist}->{name} =~ s[-][::]smgr;

        if ( $main_module->$* =~ m[=head1\s+NAME\s*$class\s*-\s*([^\n]+)]smi ) {
            $meta->{abstract} = $1;
        }

        # fill resources
        if ( my $upstream = $self->dist->scm->upstream ) {
            P->hash->merge( $meta->{resources}, $upstream->meta_resources );
        }

        P->hash->merge( $meta->{resources}, $self->dist->cfg->{dist}->{meta} ) if $self->dist->cfg->{dist}->{meta};

        # optional features
        {
            if ( my @features = $cpanfile->features ) {

                my $features = {};

                for my $feature (@features) {
                    $features->{ $feature->identifier } = {
                        description => $feature->description,
                        prereqs     => $feature->prereqs->as_string_hash,
                    };
                }

                $meta->{optional_features} = $features;
            }
        }

        # prereqs
        {
            $prereqs->requirements_for( 'configure', 'requires' )->add_minimum( 'Module::Build::Tiny' => $mbt_version );

            $meta->{prereqs} = $prereqs->as_string_hash;
        }

        require CPAN::Meta;

        CPAN::Meta->create($meta)->save('META.json');
    }

    return;
}

sub _create_temp_build ($self) {

    # TODO
    # copy files to the temp dir;
    # copy and rename xt/tests according to tests mode;
    # generate MANIFEST;
    # return temp dir;

    return;
}

sub log ( $self, $message ) {    ## no critic qw[Subroutines::ProhibitBuiltinHomonyms]
    say '[#] ' . $message;

    return;
}

sub quit ( $self, $message = undef ) {
    say '[#] ' . $message if $message;

    exit;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │                      │ Subroutines::ProhibitUnusedPrivateSubroutines                                                                  │
## │      │ 7                    │ * Private subroutine/method '_update_dist' declared but not used                                               │
## │      │ 144                  │ * Private subroutine/method '_create_temp_build' declared but not used                                         │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    2 │ 45                   │ ValuesAndExpressions::ProhibitLongChainsOfMethodCalls - Found method-call chain of length 5                    │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    1 │ 94                   │ RegularExpressions::ProhibitEnumeratedClasses - Use named character classes ([0-9] vs. \d)                     │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Dist::BuilderUtil

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
