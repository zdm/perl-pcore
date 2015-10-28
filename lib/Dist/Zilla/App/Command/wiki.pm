package Dist::Zilla::App::Command::wiki;

use strict;
use warnings;
use utf8;
use Dist::Zilla::App qw[-command];
use Pod::Markdown;

sub abstract {
    my ($self) = @_;

    return 'generate wiki docs (Pcore)';
}

sub opt_spec {
    my ( $self, $app ) = @_;

    return;
}

sub validate_args {
    my ( $self, $opt, $args ) = @_;

    # NOTE args is just raw array or params, that not described as options

    die 'no args expected' if @{$args};

    return;
}

sub execute {
    my ( $self, $opt, $args ) = @_;

    if ( !$INC{'Pcore.pm'} ) {
        print qq[Pcore is required to run this command\n];

        return;
    }

    my $header = qq[**!!! DO NOT EDIT. This document is generated automatically. !!!**\x0A\x0A];

    if ( !-d 'wiki/.hg' ) {
        print qq[no wiki repository was found\n];
    }
    else {
        my $base_url = $self->_get_base_url . q[/];

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

sub _get_base_url {
    if ( -f 'wiki/.hg/hgrc' ) {
        my $hgrc = Pcore->file->read_text('wiki/.hg/hgrc');

        if ( ${$hgrc} =~ /default\s*=\s*(.+?)$/sm ) {
            my $repo_url = $1;

            my $uri = Pcore->uri($repo_url);

            return $uri->path;
        }
    }

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "common" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 9                    │ NamingConventions::ProhibitAmbiguousNames - Ambiguously named subroutine "abstract"                            │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 26                   │ ErrorHandling::RequireCarping - "die" used instead of "croak"                                                  │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    2 │ 1                    │ Modules::RequireVersionVar - No package-scoped "$VERSION" variable found                                       │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    2 │ 40, 79               │ ValuesAndExpressions::ProhibitEscapedCharacters - Numeric escapes in interpolated string                       │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    1 │ 1                    │ NamingConventions::Capitalization - Package "Dist::Zilla::App::Command::wiki" does not start with a upper case │
## │      │                      │ letter                                                                                                         │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    1 │ 35, 43               │ InputOutput::RequireCheckedSyscalls - Return value of flagged function ignored - print                         │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=cut
