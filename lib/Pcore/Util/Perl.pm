package Pcore::Util::Perl;

use Pcore;

no Pcore;

sub module_info ( $self, @args ) {
    require Pcore::Util::Perl::ModuleInfo;

    return Pcore::Util::Perl::ModuleInfo->new(@args);
}

sub moo ( $self, @args ) {
    require Pcore::Util::Perl::Moo;

    return 'Pcore::Util::Perl::Moo';
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::Perl - perl code utils

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
