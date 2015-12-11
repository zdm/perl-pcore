package    # hide from pause
  Inline;

use Pcore;

no Pcore;

if ( $PROC->is_par ) {
    $INC{'Inline.pm'} = 1;    ## no critic qw[Variables::RequireLocalizedPunctuationVars]

    require DynaLoader;

    *import = sub {
        my $caller = caller;

        no strict qw[refs];

        push *{ $caller . '::ISA' }->@*, 'DynaLoader';

        DynaLoader::bootstrap($caller);

        return;
    };
}
else {
    require Inline;

    Inline->import(
        config => (
            directory         => $PROC->{INLINE_DIR},
            autoname          => 0,
            clean_after_build => 1,
            clean_build_area  => 1,
        )
    );
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Inline

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
