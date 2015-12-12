package Pcore::Dist::Build::Update;

use Pcore qw[-class];
use Pod::Markdown;

has dist => ( is => 'ro', isa => InstanceOf ['Pcore::Dist'], required => 1 );

no Pcore;

sub run ($self) {
    $self->update_readme_md;

    $self->update_license;

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
    $parser->parse_string_document( $self->dist->module->content->$* );

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

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    2 │ 30                   │ ValuesAndExpressions::ProhibitLongChainsOfMethodCalls - Found method-call chain of length 4                    │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Dist::Build::Update - sync dist root with sources

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
