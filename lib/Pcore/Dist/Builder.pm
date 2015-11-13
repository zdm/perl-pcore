package Pcore::Dist::Builder;

use Pcore qw[-class];
use Module::CPANfile;

has dist => ( is => 'ro', isa => InstanceOf ['Pcore::Dist'], required => 1 );

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
                        $parser->parse_string_document( ${ Pcore->file->read_bin($path) } );

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

# sub _cmd_build ($self) {
#     my $cpanfile = Module::CPANfile->load('cpanfile');
#
#     say dump $cpanfile;
#
#     # TODO build workflow
#     # - validate dist.perl config;
#     # - generate README.md, Build.PL, META.json, LICENSE;
#     # - copy all files to the temp build dir;
#     # - generate MANIFEST;
#
#     # say dump $self->dist->hg->cmd('id', '-inbt');
#
#     return;
# }

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │                      │ Subroutines::ProhibitUnusedPrivateSubroutines                                                                  │
## │      │ 23                   │ * Private subroutine/method '_cmd_test' declared but not used                                                  │
## │      │ 28                   │ * Private subroutine/method '_cmd_smoke' declared but not used                                                 │
## │      │ 32                   │ * Private subroutine/method '_cmd_clean' declared but not used                                                 │
## │      │ 65                   │ * Private subroutine/method '_cmd_deploy' declared but not used                                                │
## │      │ 71                   │ * Private subroutine/method '_cmd_par' declared but not used                                                   │
## │      │ 83                   │ * Private subroutine/method '_cmd_release' declared but not used                                               │
## │      │ 87                   │ * Private subroutine/method '_cmd_wiki' declared but not used                                                  │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    2 │ 66, 72, 96           │ ValuesAndExpressions::ProhibitLongChainsOfMethodCalls - Found method-call chain of length 4                    │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    2 │ 88, 131              │ ValuesAndExpressions::ProhibitEscapedCharacters - Numeric escapes in interpolated string                       │
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
