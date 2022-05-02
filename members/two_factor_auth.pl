#!/usr/bin/perl

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

use CGI qw(-utf8);

use C4::Auth qw( get_template_and_user );
use C4::Output qw( output_and_exit output_html_with_http_headers );

use Koha::Patrons;
use Koha::Auth::TwoFactorAuth;
use Koha::Token;

my $cgi = CGI->new;

my ( $template, $loggedinuser, $cookie ) = get_template_and_user(
    {
        template_name => 'members/two_factor_auth.tt',
        query         => $cgi,
        type          => 'intranet',
        flagsrequired => { editcatalogue => '*' },
    }
);

unless ( C4::Context->preference('TwoFactorAuthentication') ) {
    print $cgi->redirect("/cgi-bin/koha/errors/404.pl");
    exit;
}

my $logged_in_user = Koha::Patrons->find($loggedinuser);

my $op = $cgi->param('op') // '';
my $csrf_pars = {
    session_id => scalar $cgi->cookie('CGISESSID'),
    token  => scalar $cgi->param('csrf_token'),
};

if ( $op eq 'register-2FA' ) {
    output_and_exit( $cgi, $cookie, $template, 'wrong_csrf_token' )
        unless Koha::Token->new->check_csrf($csrf_pars);

    my $pin_code = $cgi->param('pin_code');
    my $secret32 = $cgi->param('secret32');
    my $auth     = Koha::Auth::TwoFactorAuth->new(
        { patron => $logged_in_user, secret32 => $secret32 } );

    my $verified = $auth->verify(
        $pin_code,
        1,    # range
        $secret32,
        undef,    # timestamp (defaults to now)
        30,       # interval (default 30)
    );

    if ($verified) {
        $logged_in_user->secret($secret32);
        $op = 'registered';

        # FIXME Generate a (new?) secret
        $logged_in_user->auth_method('two-factor')->store;
    }
    else {
        $template->param( invalid_pin => 1, );
        $op = 'enable-2FA';
    }
}

if ( $op eq 'enable-2FA' ) {

    my $secret = Koha::AuthUtils::generate_salt( 'weak', 16 );
    my $auth = Koha::Auth::TwoFactorAuth->new(
        { patron => $logged_in_user, secret => $secret } );

    $template->param(
        issuer      => $auth->issuer,
        key_id      => $auth->key_id,
        qr_code  => $auth->qr_code,
        secret32    => $auth->secret32,
            # IMPORTANT: get secret32 after qr_code call !
    );
    $auth->clear;
    $op = 'register';
}
elsif ( $op eq 'disable-2FA' ) {
    output_and_exit( $cgi, $cookie, $template, 'wrong_csrf_token' )
        unless Koha::Token->new->check_csrf($csrf_pars);
    $logged_in_user->auth_method('password')->store;
}

$template->param(
    csrf_token => Koha::Token->new->generate_csrf(
        { session_id => scalar $cgi->cookie('CGISESSID') }
    ),
    patron => $logged_in_user,
    op     => $op,
);

output_html_with_http_headers $cgi, $cookie, $template->output;
