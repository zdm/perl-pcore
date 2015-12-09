package Pcore::Dist::Build::Update;

use Pcore qw[-class];
use Pod::Markdown;
use CPAN::Meta;

has dist => ( is => 'ro', isa => InstanceOf ['Pcore::Dist'], required => 1 );

has cpanfile => ( is => 'lazy', isa => Object, init_arg => undef );
has prereqs  => ( is => 'lazy', isa => Object, init_arg => undef );

has module_build_tiny_ver => ( is => 'lazy', default => sub { version->parse(v0.39.0) }, init_arg => undef );
has test_pod_ver          => ( is => 'lazy', default => sub { version->parse(v1.51.0) }, init_arg => undef );

no Pcore;

sub _build_main_module ($self) {
    return P->file->read_bin( $self->dist->main_module_path );
}

sub _build_cpanfile ($self) {
    return P->class->load('Module::CPANfile')->load( $self->dist->root . 'cpanfile' );
}

sub _build_prereqs ($self) {
    return $self->cpanfile->prereqs;
}

sub run ($self) {

    # drop cached info
    $self->dist->clear;

    $self->update_readme_md;

    $self->update_license;

    $self->update_build_pl;

    $self->update_meta_json;

    return;
}

sub update_readme_md ($self) {
    my $parser = Pod::Markdown->new(

        # perldoc_url_prefix       => $base_url,
        perldoc_fragment_format  => 'pod_simple_html',    # CodeRef ( $self, $text )
        markdown_fragment_format => 'pod_simple_html',    # CodeRef ( $self, $text )
        include_meta_tags        => 0,
    );

    $parser->output_string( \my $markdown );

    # generate markdown document
    $parser->parse_string_document( $self->dist->main_module->content->$* );

    P->file->write_bin( $self->dist->root . 'README.md', $markdown );

    return;
}

sub update_license ($self) {
    my $lic = P->class->load( $self->dist->cfg->{dist}->{license}, ns => 'Software::License' )->new(
        {   holder => $self->dist->cfg->{dist}->{copyright_holder} || $self->dist->cfg->{dist}->{author},
            year => P->date->now->year,
        }
    );

    P->file->write_bin( $self->dist->root . 'LICENSE', $lic->fulltext );

    return;
}

sub update_build_pl ($self) {
    my $reqs = $self->prereqs->merged_requirements( [qw/configure build test runtime/], ['requires'] );

    my $min_perl = $reqs->requirements_for_module('perl') || $];

    my $mbt_version = $self->module_build_tiny_ver;

    my $template = <<"BUILD_PL";
use strict;
use warnings;

use $min_perl;
use Module::Build::Tiny $mbt_version;
Build_PL();
BUILD_PL

    P->file->write_bin( $self->dist->root . 'Build.PL', $template );

    return;
}

sub update_meta_json ($self) {
    my $meta = {
        abstract => 'unknown',
        author   => [            #
            $self->dist->cfg->{dist}->{author},
        ],
        dynamic_config => 0,
        license        => [ lc $self->dist->cfg->{dist}->{license} ],
        name           => $self->dist->name,
        no_index       => {                                             #
            directory => [qw[share t]],
        },
        release_status => 'stable',
        version        => undef,
    };

    # version
    $meta->{version} = $self->dist->main_module->version;

    # abstract
    $meta->{abstract} = $self->dist->main_module->abstract if $self->dist->main_module->abstract;

    # resources
    my $upstream_meta = $self->dist->scm && $self->dist->scm->upstream ? $self->dist->scm->upstream->meta_resources : {};

    if ( my $val = $self->dist->cfg->{dist}->{meta}->{homepage} || $upstream_meta->{homepage} ) {
        $meta->{resources}->{homepage} = $val;
    }

    if ( my $val = $self->dist->cfg->{dist}->{meta}->{repository}->{web} || $upstream_meta->{repository}->{web} ) {
        $meta->{resources}->{repository}->{web} = $val;
    }

    if ( my $val = $self->dist->cfg->{dist}->{meta}->{repository}->{url} || $upstream_meta->{repository}->{url} ) {
        $meta->{resources}->{repository}->{url} = $val;
    }

    if ( my $val = $self->dist->cfg->{dist}->{meta}->{repository}->{type} || $upstream_meta->{repository}->{type} ) {
        $meta->{resources}->{repository}->{type} = $val;
    }

    if ( my $val = $self->dist->cfg->{dist}->{meta}->{bugtracker}->{web} || $upstream_meta->{bugtracker}->{web} ) {
        $meta->{resources}->{bugtracker}->{web} = $val;
    }

    # optional features
    if ( my @features = $self->cpanfile->features ) {

        my $features = {};

        for my $feature (@features) {
            $features->{ $feature->identifier } = {
                description => $feature->description,
                prereqs     => $feature->prereqs->as_string_hash,
            };
        }

        $meta->{optional_features} = $features;
    }

    # prereqs
    $self->prereqs->requirements_for( 'configure', 'requires' )->add_minimum( 'Module::Build::Tiny' => $self->module_build_tiny_ver );

    $self->prereqs->requirements_for( 'develop', 'requires' )->add_minimum( 'Test::Pod' => $self->test_pod_ver );

    $meta->{prereqs} = $self->prereqs->as_string_hash;

    # create and store META.json
    P->file->write_text( $self->dist->root . 'META.json', { crlf => 0 }, CPAN::Meta->create($meta)->as_string );

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    2 │ 57, 120              │ ValuesAndExpressions::ProhibitLongChainsOfMethodCalls - Found method-call chain of length 4                    │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Dist::Build::Update

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
