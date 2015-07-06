package Pcore::API::Class::Tree::Heterogenous;

use Pcore qw[-role];

with qw[Pcore::API::Class::Tree];

our $FIELDS = {

    # system fields
    node_type => { type => 'str', persist => 'rw' },
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
            ADD COLUMN IF NOT EXISTS `node_type` INT UNSIGNED NOT NULL
        ;
    ];

    $self->run_ddl( $sql, [qw[TRADITIONAL ALLOW_INVALID_DATES]] );

    return;
};

around ext_class_model => sub {
    my $orig = shift;
    my $self = shift;

    my $class = $self->$orig;

    $class->cfg->{proxy}->{reader}->{typeProperty} = 'nodeType';    # The name of the property in a node raw data block which indicates the type of the model to be created from that raw data

    return $class;
};

no Pcore;

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 31, 32               │ ValuesAndExpressions::ProhibitImplicitNewlines - Literal line breaks in a string                               │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=cut
