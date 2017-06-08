package Pcore::Util::Scalar;

use Pcore -export => {
    SCALAR => [qw[blessed refaddr reftype weaken isweak looks_like_number tainted refcount]],
    REF    => [qw[is_ref is_scalarref is_arrayref is_hashref is_coderef is_regexpref is_globref is_formatref is_ioref is_refref is_plain_ref is_plain_scalarref is_plain_arrayref is_plain_hashref is_plain_coderef is_plain_globref is_plain_formatref is_plain_refref is_blessed_ref is_blessed_scalarref is_blessed_arrayref is_blessed_hashref is_blessed_coderef is_blessed_globref is_blessed_formatref is_blessed_refref ]],
};
use Scalar::Util qw[blessed dualvar isdual readonly refaddr reftype tainted weaken isweak isvstring looks_like_number set_prototype];    ## no critic qw[Modules::ProhibitEvilModules]
use Devel::Refcount qw[refcount];
use Ref::Util qw[:all];

sub on_destroy ( $scalar, $cb ) {
    state $init = !!require Variable::Magic;

    Variable::Magic::cast( $_[0], Variable::Magic::wizard( free => $cb ) );

    return;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::Scalar

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
