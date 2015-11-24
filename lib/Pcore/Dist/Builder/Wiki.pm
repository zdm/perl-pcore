package Pcore::Dist::Builder::Wiki;

use Pcore qw[-class];

with qw[Pcore::Dist::Builder];

no Pcore;

sub cli_run ( $self, $opt, $arg, $rest ) {
    $self->new->run;

    return;
}

sub run ($self) {
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

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    2 │ 16, 59               │ ValuesAndExpressions::ProhibitEscapedCharacters - Numeric escapes in interpolated string                       │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    2 │ 24                   │ ValuesAndExpressions::ProhibitLongChainsOfMethodCalls - Found method-call chain of length 4                    │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Dist::Builder::Wiki - generate wiki pages

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
