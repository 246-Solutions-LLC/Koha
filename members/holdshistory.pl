#!/usr/bin/perl
#
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

use CGI qw ( -utf8 );

use C4::Auth   qw( get_template_and_user );
use C4::Output qw( output_html_with_http_headers );

use Koha::Patrons;

my $input = CGI->new;

my ( $template, $loggedinuser, $cookie ) = get_template_and_user(
    {
        template_name => "members/holdshistory.tt",
        query         => $input,
        type          => "intranet",
        flagsrequired => { borrowers => 'edit_borrowers' },
    }
);

my $cardnumber     = $input->param('cardnumber');
my $borrowernumber = $input->param('borrowernumber');
my $patron         = Koha::Patrons->find( $cardnumber ? { cardnumber => $cardnumber } : $borrowernumber );

unless ($patron) {
    print $input->redirect("/cgi-bin/koha/circ/circulation.pl?borrowernumber=$borrowernumber");
    exit;
}

$template->param(
    holdshistoryview => 1,
    patron           => $patron,
);

output_html_with_http_headers $input, $cookie, $template->output;
