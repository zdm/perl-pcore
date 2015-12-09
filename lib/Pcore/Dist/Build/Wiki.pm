package Pcore::Dist::Build::Wiki;

use Pcore qw[-class];
use Pod::Markdown;

has dist => ( is => 'ro', isa => InstanceOf ['Pcore::Dist'], required => 1 );

around new => sub ( $orig, $self, $args ) {
    return if !-d $args->{dist}->root . 'wiki/.hg/';

    return $self->$orig($args);
};

no Pcore;

sub update ($self) {
    my $chdir_guard = P->file->chdir( $self->dist->root );

    my $wiki_path = P->path('wiki/')->realpath;

    my $header = qq[**!!! DO NOT EDIT. This document is generated automatically. !!!**$LF$LF];

    my $upstream = P->class->load('Pcore::Src::SCM')->new($wiki_path)->upstream;

    my $base_url = q[/] . $upstream->username . q[/] . $upstream->reponame . q[/wiki/];

    Pcore->file->rmtree( $wiki_path . 'POD/' );

    my $toc = [];

    # scan lib/ for .pm files
    Pcore->file->find(
        './lib/',
        dir => 0,
        sub ($path) {
            if ( $path->suffix eq 'pm' ) {
                my $parser = Pod::Markdown->new(
                    perldoc_url_prefix       => $base_url,
                    perldoc_fragment_format  => 'pod_simple_html',    # CodeRef ( $self, $text )
                    markdown_fragment_format => 'pod_simple_html',    # CodeRef ( $self, $text )
                    include_meta_tags        => 0,
                );

                my $pod_markdown;

                $parser->output_string( \$pod_markdown );

                # generate markdown document
                $parser->parse_string_document( P->file->read_bin($path)->$* );

                $pod_markdown =~ s/\n+\z//smg;

                if ($pod_markdown) {
                    my $markdown = $header;

                    $markdown .= "[POD index](${base_url}POD)$LF$LF";

                    $markdown .= "[TOC]$LF$LF";

                    $markdown .= $pod_markdown;

                    # write markdown to the file
                    Pcore->file->mkpath( $wiki_path . 'POD/' . $path->dirname );

                    push $toc->@*, $path->dirname . $path->filename_base;

                    Pcore->file->write_text( $wiki_path . 'POD/' . $path->dirname . $path->filename_base . q[.md], { crlf => 0 }, \$markdown );
                }
            }
        }
    );

    # generate POD.md
    my $toc_md = $header;

    for my $link ( sort $toc->@* ) {
        my $indent = $link =~ tr[/][/];

        my $package_name = $link =~ s[/][::]smgr;

        $toc_md .= q[ ] x $indent . " [${package_name}](${base_url}POD/${link})$LF$LF";
    }

    # write POD.md
    Pcore->file->write_text( $wiki_path . 'POD.md', { crlf => 0 }, \$toc_md );

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    2 │ 23                   │ ValuesAndExpressions::ProhibitLongChainsOfMethodCalls - Found method-call chain of length 4                    │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Dist::Build::Wiki - generate wiki pages

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
