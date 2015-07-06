package Dist::Zilla::MintingProfile::Pcore;

use Moose;
use Pcore;
use Path::Class qw[];

with qw[Dist::Zilla::Role::MintingProfile];

no Pcore;
no Moose;

sub profile_dir ( $self, $profile_name ) {
    my $profile_dir = Path::Class::dir( $P->{SHARE_DIR} . 'pcore/' )->subdir($profile_name);

    return $profile_dir;
}

__PACKAGE__->meta->make_immutable;

1;
__END__
=pod

=encoding utf8

=head1 NAME

Dist::Zilla::MintingProfile::Pcore

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
