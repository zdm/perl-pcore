package Pcore::Dist::Builder;

use Pcore qw[-class];
use Module::CPANfile;

has dist => ( is => 'ro', isa => InstanceOf ['Pcore::Dist'], required => 1 );

# perl CPAN distribution
# http://www.perlmonks.org/?node_id=1009586

around new => sub ( $orig, $self, $dist ) {
    return $self->$orig( { dist => $dist } );
};

no Pcore;

sub run ( $self, $cmd, $args ) {
    my $chdir_guard = P->file->chdir( $self->dist->root );

    my $method = '_cmd_' . $cmd;

    return $self->$method($args);
}

# TODO
sub _cmd_test ( $self, $args ) {
    $self->_update_dist;

    return;
}

# TODO
sub _cmd_smoke ( $self, $args ) {
    return;
}

sub _cmd_clean ( $self, $args ) {
    my $dirs = [

        # general build
        'blib',

        # Module::Build
        '_build',
    ];

    my $files = [

        # general build
        qw[META.yml MYMETA.json MYMETA.yml],

        # Module::Build
        qw[_build_params Build Build.bat],

        # MakeMaker
        qw[Makefile pm_to_blib],
    ];

    for my $dir ( $dirs->@* ) {
        P->file->rmtree($dir);
    }

    for my $file ( $files->@* ) {
        unlink $file or die qq[Can't unlink "$file"] if -f $file;
    }

    return;
}

sub _cmd_deploy ( $self, $args ) {
    P->class->load( 'Deploy', ns => 'Pcore::Dist::Builder' )->new( { builder => $self } )->run($args);

    return;
}

sub _cmd_par ( $self, $args ) {
    P->class->load( 'PAR', ns => 'Pcore::Dist::Builder' )->new( { builder => $self } )->build_par(
        release => $args->{release} // 0,
        crypt   => $args->{crypt}   // 0,
        noupx   => $args->{noupx}   // 0,
        clean   => $args->{clean}   // 0,
    );

    return;
}

# TODO
sub _cmd_release ( $self, $args ) {
    return;
}

sub _cmd_wiki ( $self, $args ) {
    my $header = qq[**!!! DO NOT EDIT. This document is generated automatically. !!!**\x0A\x0A];

    if ( !-d 'wiki/.hg' ) {
        print qq[no wiki repository was found\n];
    }
    else {
        require Pod::Markdown;

        my $upstream = P->class->load('Pcore::Src::SCM')->new('./wiki/')->upstream;

        my $base_url = q[/] . $upstream->username . q[/] . $upstream->reponame . q[/wiki/];

        Pcore->file->rmtree('wiki/POD/');

        my $toc = [];

        # scan lib/ for .pm files
        Pcore->file->find(
            {   wanted => sub {
                    return if -d;

                    my $path = Pcore->path($_);

                    if ( $path->suffix eq 'pm' ) {
                        my $parser = Pod::Markdown->new(
                            perldoc_url_prefix       => $base_url,
                            perldoc_fragment_format  => 'pod_simple_html',    # CodeRef ( $self, $text )
                            markdown_fragment_format => 'pod_simple_html',    # CodeRef ( $self, $text )
                            include_meta_tags        => 0,
                        );

                        my $markdown;

                        $parser->output_string( \$markdown );

                        # generate markdown document
                        $parser->parse_string_document( P->file->read_bin($path)->$* );

                        $markdown =~ s/\n+\z//smg;

                        if ($markdown) {

                            # add common header, TOC link
                            $markdown = $header . qq[# [TABLE OF CONTENTS](${base_url}POD)\x0A\x0A] . $markdown;

                            # write markdown to the file
                            my $out_path = $path->dirname =~ s[\Alib/][]smr;

                            Pcore->file->mkpath( 'wiki/POD/' . $out_path );

                            push @{$toc}, $out_path . $path->filename_base;

                            Pcore->file->write_text( 'wiki/POD/' . $out_path . $path->filename_base . q[.md], { crlf => 0 }, \$markdown );
                        }
                    }
                },
                no_chdir => 1,
            },
            q[lib/]
        );

        # generate TOC
        my $toc_md = $header;

        for my $link ( @{$toc} ) {
            my $package_name = $link =~ s[/][::]smgr;

            $toc_md .= qq[## [${package_name}](${base_url}POD/${link})\n\n];
        }

        Pcore->file->write_text( 'wiki/POD.md', { crlf => 0 }, \$toc_md );
    }

    return;
}

# TODO main_module can be removed;
# copyright_year can be removed;
# copyright holder can be omitted, then author should be used;
# Pcore - no warnings experimental only for perl 5.22.*
sub _update_dist ($self) {

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
        $parser->parse_string_document( P->file->read_bin( $self->dist->cfg->{dist}->{main_module} )->$* );

        P->file->write_bin( 'README.md', $markdown );
    }

    # generate LICENSE
    {
        P->file->write_bin(
            'LICENSE',
            P->class->load( $self->dist->cfg->{dist}->{license}, ns => 'Software::License' )->new(
                {   holder => $self->dist->cfg->{dist}->{copyright_holder},
                    year   => $self->dist->cfg->{dist}->{copyright_year},
                }
            )->fulltext
        );
    }

    my $cpanfile = P->class->load('Module::CPANfile')->load('cpanfile');

    my $prereqs = $cpanfile->prereqs;

    # generate Build.PL
    {
        my $reqs = $prereqs->merged_requirements( [qw/configure build test runtime/], ['requires'] );

        my $min_perl = $reqs->requirements_for_module('perl') || '5.006';

        my $mbt_version = P->class->load('Module::Metadata')->new_from_module('Module::Build::Tiny')->version->stringify;

        if ($mbt_version) {
            $mbt_version = q[ ] . $mbt_version;
        }
        else {
            $mbt_version = q[];
        }

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
        # TODO $self->zilla->register_prereqs({ phase => 'configure' }, 'Module::Build::Tiny' => $self->version);
        require CPAN::Meta;

        say dump $cpanfile->prereq_specs;
    }

    return;
}

sub _create_temp_build ($self) {

    # TODO
    # copy files to the temp dir;
    # generate MANIFEST;

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │                      │ Subroutines::ProhibitUnusedPrivateSubroutines                                                                  │
## │      │ 26                   │ * Private subroutine/method '_cmd_test' declared but not used                                                  │
## │      │ 33                   │ * Private subroutine/method '_cmd_smoke' declared but not used                                                 │
## │      │ 37                   │ * Private subroutine/method '_cmd_clean' declared but not used                                                 │
## │      │ 70                   │ * Private subroutine/method '_cmd_deploy' declared but not used                                                │
## │      │ 76                   │ * Private subroutine/method '_cmd_par' declared but not used                                                   │
## │      │ 88                   │ * Private subroutine/method '_cmd_release' declared but not used                                               │
## │      │ 92                   │ * Private subroutine/method '_cmd_wiki' declared but not used                                                  │
## │      │ 251                  │ * Private subroutine/method '_create_temp_build' declared but not used                                         │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    2 │                      │ ValuesAndExpressions::ProhibitLongChainsOfMethodCalls                                                          │
## │      │ 71, 77, 101, 200     │ * Found method-call chain of length 4                                                                          │
## │      │ 219                  │ * Found method-call chain of length 5                                                                          │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    2 │ 93, 136              │ ValuesAndExpressions::ProhibitEscapedCharacters - Numeric escapes in interpolated string                       │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Dist::Builder

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
