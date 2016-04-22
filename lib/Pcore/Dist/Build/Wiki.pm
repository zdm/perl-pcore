package Pcore::Dist::Build::Wiki;

use Pcore -class;
use Pod::Markdown;
use Pcore::API::SCM;

has dist => ( is => 'ro', isa => InstanceOf ['Pcore::Dist'], required => 1 );

around new => sub ( $orig, $self, $args ) {
    return if !-d $args->{dist}->root . 'wiki/';

    return $self->$orig($args);
};

sub run ($self) {
    my $chdir_guard = P->file->chdir( $self->dist->root );

    my $wiki_path = P->path('wiki/')->realpath;

    my $scm = Pcore::API::SCM->new($wiki_path);

    my $upstream = $scm->upstream;

    my $base_url = q[/] . $upstream->namespace . q[/] . $upstream->repo_name . q[/wiki/];

    P->file->rmtree( $wiki_path . 'POD/' );

    my $toc = {};

    # scan lib/ for .pm files
    P->file->find(
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

                my $module = P->perl->module($path);

                my $pod_markdown;

                $parser->output_string( \$pod_markdown );

                # generate markdown document
                $parser->parse_string_document( $module->content->$* );

                $pod_markdown =~ s/\n+\z//smg;

                if ($pod_markdown) {
                    my $markdown = <<"MD";
**!!! DO NOT EDIT. This document is generated automatically. !!!**

back to **[INDEX](${base_url}POD)**

**TABLE OF CONTENT**

[TOC]

$pod_markdown
MD

                    # write markdown to the file
                    P->file->mkpath( $wiki_path . 'POD/' . $path->dirname );

                    $toc->{ $path->dirname . $path->filename_base } = $module->abstract;

                    P->file->write_text( $wiki_path . 'POD/' . $path->dirname . $path->filename_base . q[.md], { crlf => 0 }, \$markdown );
                }
            }
        }
    );

    # generate POD.md
    my $toc_md = <<'MD';
**!!! DO NOT EDIT. This document is generated automatically. !!!**

MD
    for my $link ( sort keys $toc->%* ) {
        my $package_name = $link =~ s[/][::]smgr;

        $toc_md .= "**[${package_name}](${base_url}POD/${link})**";

        # add abstract
        $toc_md .= " - $toc->{$link}" if $toc->{$link};

        $toc_md .= "  $LF";    # two spaces make single line break
    }

    # write POD.md
    P->file->write_text( $wiki_path . 'POD.md', { crlf => 0 }, \$toc_md );

    say keys( $toc->%* ) + 1 . ' wiki page(s) were generated';

    if ( !$scm->scm_is_commited ) {
        $scm->scm_addremove;

        $scm->scm_commit('auto updated');

        print 'Pushing wiki ... ';

        my $res = $scm->scm_push;

        say $res->reason;
    }

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 83, 97               | References::ProhibitDoubleSigils - Double-sigil dereference                                                    |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 97                   | ValuesAndExpressions::ProhibitMismatchedOperators - Mismatched operator                                        |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
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
