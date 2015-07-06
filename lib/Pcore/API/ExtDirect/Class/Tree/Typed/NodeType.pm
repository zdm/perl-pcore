package Pcore::API::Class::Tree::Typed::NodeType;

use Pcore qw[-role];

with qw[Pcore::API::Class::Grid];

our $FIELDS = {
    text  => { type => 'str', persist => 'rw', write_field => 1 },
    class => { type => 'str', persist => 'rw', write_field => 1 },
};

around BUILD => sub {
    my $orig = shift;
    my $self = shift;

    $self->$orig(@_);

    $self->add_fields($FIELDS);

    return;
};

# DDL
around APP_BUILD => sub {
    my $orig = shift;
    my $self = shift;

    $self->$orig;

    my $sql = q[
        ALTER TABLE ] . $self->dbh->quote_id( $self->table ) . q[
            ADD COLUMN IF NOT EXISTS `text` VARCHAR(32) NOT NULL,
            ADD COLUMN IF NOT EXISTS `class` VARCHAR(32) NOT NULL,
            ADD UNIQUE INDEX IF NOT EXISTS `] . $self->table . q[_text_UNIQUE` (`text` ASC),
            ADD UNIQUE INDEX IF NOT EXISTS `] . $self->table . q[_class_UNIQUE` (`class` ASC)
        ;
    ];

    $self->run_ddl( $sql, [qw[TRADITIONAL ALLOW_INVALID_DATES]] );

    return;
};

no Pcore;

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 30, 31, 34, 35       │ ValuesAndExpressions::ProhibitImplicitNewlines - Literal line breaks in a string                               │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=cut
