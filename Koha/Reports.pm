package Koha::Reports;

# This file is part of Koha.
#
# Koha is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# Koha is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Koha; if not, see <http://www.gnu.org/licenses>.

use Modern::Perl;

use Koha::Database;

use Koha::Report;

use base qw(Koha::Objects Koha::Objects::Limit::Library);

=head1 NAME

Koha::Reports - Koha Report Object set class

=head1 API

=head2 Class Methods

=cut

=head3 search_with_localization

=cut

sub search_with_localization {
    my ( $self, $params, $attributes ) = @_;

    my $language = C4::Languages::getlanguage();
    $Koha::Schema::Result::Itemtype::LANGUAGE = $language;
    $attributes->{order_by}                   = 'translated_description' unless exists $attributes->{order_by};
    $attributes->{join}                       = 'localization';
    $attributes->{'+select'}                  = [
        {
            coalesce => [qw( localization.translation me.description )],
            -as      => 'translated_description'
        }
    ];
    if ( defined $params->{branchcode} ) {
        my $branchcode = delete $params->{branchcode};
        $self->search_with_library_limits( $params, $attributes, $branchcode );
    } else {
        $self->SUPER::search( $params, $attributes );
    }
}

=head3 _type

Returns name of corresponding DBIC resultset

=cut

sub _type {
    return 'SavedSql';
}

=head3 object_class

Returns name of corresponding Koha Object Class

=cut

sub object_class {
    return 'Koha::Report';
}

=head1 AUTHOR

Kyle M Hall <kyle@bywatersolutions.com>

=cut

1;
