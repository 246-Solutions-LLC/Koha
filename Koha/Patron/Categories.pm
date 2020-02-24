package Koha::Patron::Categories;

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

use Carp;

use C4::Context; # Sigh...

use Koha::Database;

use Koha::Patron::Category;

use base qw(Koha::Objects);

=head1 NAME

Koha::Patron::Categories - Koha Patron Category Object set class

=head1 API

=head2 Class Methods

=cut

sub search_limited {
    my ( $self, $params, $attributes ) = @_;
    my $branch_limit = C4::Context->userenv ? C4::Context->userenv->{"branch"} : "";
    if ( $branch_limit ) {
        $params->{'categories_branches.branchcode'} = [ $branch_limit, undef ];
        $attributes->{join} = 'categories_branches';
    }
    $attributes->{order_by} = ['description'] unless $attributes->{order_by};
    return $self->search($params, $attributes);
}

=head3 type

=cut

sub _type {
    return 'Category';
}

sub object_class {
    return 'Koha::Patron::Category';
}

1;
