#!/usr/bin/perl

# This file is part of Koha
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

use Test::NoWarnings;
use Test::More tests => 11;

use Koha::Report;
use Koha::Reports;
use Koha::Database;

use t::lib::Mocks;
use t::lib::TestBuilder;

my $schema = Koha::Database->new->schema;
$schema->storage->txn_begin;

my $builder       = t::lib::TestBuilder->new;
my $nb_of_reports = Koha::Reports->search->count;
my $new_report_1  = Koha::Report->new(
    {
        report_name => 'report_name_for_test_1',
        savedsql    => 'SELECT "I wrote a report"',
    }
)->store;
my $new_report_2 = Koha::Report->new(
    {
        report_name => 'report_name_for_test_1',
        savedsql    => 'SELECT "Oops, I did it again"',
    }
)->store;

like( $new_report_1->id, qr|^\d+$|, 'Adding a new report should have set the id' );
is( Koha::Reports->search->count, $nb_of_reports + 2, 'The 2 reports should have been added' );

my $retrieved_report_1 = Koha::Reports->find( $new_report_1->id );
is(
    $retrieved_report_1->report_name, $new_report_1->report_name,
    'Find a report by id should return the correct report'
);

$retrieved_report_1->delete;
is( Koha::Reports->search->count, $nb_of_reports + 1, 'Delete should have deleted the report' );

subtest 'prep_report' => sub {
    plan tests => 4;

    my $report = Koha::Report->new(
        {
            report_name => 'report_name_for_test_1',
            savedsql    => 'SELECT * FROM items WHERE itemnumber IN <<Test|list>>',
        }
    )->store;
    my $id = $report->id;

    my ( $sql, undef ) = $report->prep_report( ['Test|list'], ["1\n12\n\r243"] );
    is(
        $sql, qq{SELECT * FROM items WHERE itemnumber IN ('1','12','243') /* saved_sql.id: $id */},
        'Expected sql generated correctly with single param and name'
    );

    $report->savedsql('SELECT * FROM items WHERE itemnumber IN <<Test|list>> AND <<Another>> AND <<Test|list>>')->store;

    ( $sql, undef ) = $report->prep_report( [ 'Test|list', 'Another' ], [ "1\n12\n\r243", 'the other' ] );
    is(
        $sql,
        qq{SELECT * FROM items WHERE itemnumber IN ('1','12','243') AND 'the other' AND ('1','12','243') /* saved_sql.id: $id */},
        'Expected sql generated correctly with multiple params and names'
    );

    ( $sql, undef ) = $report->prep_report( [], [ "1\n12\n\r243", 'the other' ] );
    is(
        $sql,
        qq{SELECT * FROM items WHERE itemnumber IN ('1','12','243') AND 'the other' AND ('1','12','243') /* saved_sql.id: $id */},
        'Expected sql generated correctly with multiple params and no names'
    );

    $report->savedsql(
        q{SELECT  i.itemnumber, i.itemnumber as Exemplarnummber, [[i.itemnumber| itemnumber for batch]] FROM items})
        ->store;
    my $headers;
    ( $sql, $headers ) = $report->prep_report( [], [] );
    is_deeply( $headers, { 'itemnumber for batch' => 'itemnumber' } );
};

subtest 'is_sql_valid' => sub {
    plan tests => 3 + 6 * 2;
    my @badwords = ( 'UPDATE', 'DELETE', 'DROP', 'INSERT', 'SHOW', 'CREATE' );
    is_deeply(
        [ Koha::Report->new( { savedsql => '' } )->is_sql_valid ],
        [ 0, [ { queryerr => 'Missing SELECT' } ] ],
        'Empty sql is missing SELECT'
    );
    is_deeply(
        [ Koha::Report->new( { savedsql => 'FOO' } )->is_sql_valid ],
        [ 0, [ { queryerr => 'Missing SELECT' } ] ],
        'Nonsense sql is missing SELECT'
    );
    is_deeply(
        [ Koha::Report->new( { savedsql => 'select FOO' } )->is_sql_valid ],
        [ 1, [] ],
        'select FOO is good'
    );
    foreach my $word (@badwords) {
        is_deeply(
            [ Koha::Report->new( { savedsql => 'select FOO;' . $word . ' BAR' } )->is_sql_valid ],
            [ 0, [ { sqlerr => $word } ] ],
            'select FOO with ' . $word . ' BAR'
        );
        is_deeply(
            [ Koha::Report->new( { savedsql => $word . ' qux' } )->is_sql_valid ],
            [ 0, [ { sqlerr => $word } ] ],
            $word . ' qux'
        );
    }
};

subtest 'check_columns' => sub {
    plan tests => 3;

    my $report = Koha::Report->new;
    is_deeply( [ $report->check_columns('SELECT passWorD from borrowers') ], ['passWorD'], 'Bad column found in SQL' );
    is( scalar $report->check_columns('SELECT reset_passWorD from borrowers'), 0, 'No bad column found in SQL' );

    is_deeply(
        [
            $report->check_columns(
                undef,
                [
                    qw(change_password hash secret test place mytoken hersecret password_expiry_days password_expiry_days2)
                ]
            )
        ],
        [qw(secret mytoken hersecret password_expiry_days2)],
        'Check column_names parameter'
    );
};

subtest '_might_add_limit' => sub {
    plan tests => 10;

    my $sql;

    t::lib::Mocks::mock_preference( 'ReportsExportLimit', undef );    # i.e. no limit
    $sql = "SELECT * FROM biblio WHERE 1";
    is( Koha::Report->_might_add_limit($sql), $sql, 'Pref is undefined, no changes' );
    t::lib::Mocks::mock_preference( 'ReportsExportLimit', 0 );        # i.e. no limit
    is( Koha::Report->_might_add_limit($sql), $sql, 'Pref is zero, no changes' );
    t::lib::Mocks::mock_preference( 'ReportsExportLimit', q{} );      # i.e. no limit
    is( Koha::Report->_might_add_limit($sql), $sql, 'Pref is empty, no changes' );
    t::lib::Mocks::mock_preference( 'ReportsExportLimit', 10 );
    like( Koha::Report->_might_add_limit($sql), qr/ LIMIT 10$/, 'Limit 10 found at the end' );
    $sql = "SELECT * FROM biblio WHERE 1 LIMIT 1000 ";
    is( Koha::Report->_might_add_limit($sql), $sql, 'Already contains a limit' );
    $sql = "SELECT * FROM biblio WHERE 1 LIMIT 1000,2000";
    is( Koha::Report->_might_add_limit($sql), $sql, 'Variation, also contains a limit' );

    # trying a subquery having a limit (testing the lookahead in regex)
    $sql = "SELECT * FROM biblio WHERE biblionumber IN (SELECT biblionumber FROM reserves LIMIT 2)";
    like( Koha::Report->_might_add_limit($sql), qr/ LIMIT 10$/, 'Subquery, limit 10 found at the end' );
    $sql = "SELECT * FROM biblio WHERE biblionumber IN (SELECT biblionumber FROM reserves LIMIT 2, 3 ) AND 1";
    like( Koha::Report->_might_add_limit($sql), qr/ LIMIT 10$/, 'Subquery variation, limit 10 found at the end' );
    $sql = "select * from biblio where biblionumber in (select biblionumber from reserves limiT 3,4) and 1";
    like( Koha::Report->_might_add_limit($sql), qr/ LIMIT 10$/, 'Subquery lc variation, limit 10 found at the end' );

    $sql = "select limit, 22 from mylimits where limit between 1 and 3";
    like(
        Koha::Report->_might_add_limit($sql), qr/ LIMIT 10$/,
        'Query refers to limit field, limit 10 found at the end'
    );
};

subtest 'reports_branches are added and removed from report_branches table' => sub {
    plan tests => 4;

    my $updated_nb_of_reports = Koha::Reports->search->count;
    my $report                = Koha::Report->new(
        {
            report_name => 'report_name_for_test_1',
            savedsql    => 'SELECT * FROM items WHERE itemnumber IN <<Test|list>>',
        }
    )->store;

    my $id       = $report->id;
    my $library1 = $builder->build_object( { class => 'Koha::Libraries' } );
    my $library2 = $builder->build_object( { class => 'Koha::Libraries' } );
    my $library3 = $builder->build_object( { class => 'Koha::Libraries' } );
    my @branches = ( $library1->branchcode, $library2->branchcode, $library3->branchcode );

    $report->replace_library_limits( \@branches );

    my @branches_loop = $report->get_library_limits->as_list;
    is( scalar @branches_loop, 3, '3 branches added to report_branches table' );

    $report->replace_library_limits( [ $library1->branchcode, $library2->branchcode ] );

    @branches_loop = $report->get_library_limits->as_list;
    is( scalar @branches_loop, 2, '1 branch removed from report_branches table' );

    $report->delete;
    is( Koha::Reports->search->count, $updated_nb_of_reports, 'Report deleted, count is back to original' );
    is(
        $schema->resultset('ReportsBranch')->search( { report_id => $id } )->count,
        0,
        'No branches left in reports_branches table after report deletion'
    );
};

subtest 'can_manage_limits and can_access' => sub {
    plan tests => 21;

    my $libraryA = $builder->build_object( { class => 'Koha::Libraries' } );
    my $libraryB = $builder->build_object( { class => 'Koha::Libraries' } );
    my $branchA  = $libraryA->branchcode;
    my $branchB  = $libraryB->branchcode;

    my $super_patron =
        $builder->build_object( { class => 'Koha::Patrons', value => { flags => 1, branchcode => $branchA } } );
    my $mgr_patron   = $builder->build_object( { class => 'Koha::Patrons', value => { branchcode => $branchA } } );
    my $basic_patron = $builder->build_object( { class => 'Koha::Patrons', value => { branchcode => $branchA } } );

    # Grant reports => manage_report_limits to manager patron (create permission if missing)
    my $perm = $schema->resultset('Permission')->find( { module_bit => 16, code => 'manage_report_limits' } )
        // $schema->resultset('Permission')
        ->create( { module_bit => 16, code => 'manage_report_limits', description => 'Manage report limits' } );
    $schema->resultset('UserPermission')
        ->create( { borrowernumber => $mgr_patron->borrowernumber, module_bit => 16, code => 'manage_report_limits' } );

    # Helper to create reports
    my $r_no = Koha::Report->new( { report_name => 'No limits', savedsql => 'SELECT 1' } )->store;
    my $r_A  = Koha::Report->new( { report_name => 'Limit A',   savedsql => 'SELECT 1' } )->store;
    my $r_B  = Koha::Report->new( { report_name => 'Limit B',   savedsql => 'SELECT 1' } )->store;
    my $r_AB = Koha::Report->new( { report_name => 'Limit AB',  savedsql => 'SELECT 1' } )->store;

    $r_A->replace_library_limits( [$branchA] );
    $r_B->replace_library_limits( [$branchB] );
    $r_AB->replace_library_limits( [ $branchA, $branchB ] );

    # Preference ON, branch A
    t::lib::Mocks::mock_preference( 'LimitReportsByBranch', 1 );
    t::lib::Mocks::mock_userenv( { branchcode => $branchA } );

    ok( Koha::Report->can_manage_limits($super_patron),  'pref ON: super manages limits' );
    ok( Koha::Report->can_manage_limits($mgr_patron),    'pref ON: manager manages limits' );
    ok( !Koha::Report->can_manage_limits($basic_patron), 'pref ON: basic cannot manage limits' );

    # Basic patron (branch A)
    ok( $r_no->can_access($basic_patron), 'pref ON: no limits accessible' );
    ok( $r_A->can_access($basic_patron),  'pref ON: limited includes branch accessible' );
    ok( !$r_B->can_access($basic_patron), 'pref ON: limited excludes branch denied' );
    ok( $r_AB->can_access($basic_patron), 'pref ON: multi includes branch accessible' );

    # Manager bypass (branch A)
    ok( $r_A->can_access($mgr_patron),  'pref ON: manager sees limited A' );
    ok( $r_B->can_access($mgr_patron),  'pref ON: manager sees limited B' );
    ok( $r_AB->can_access($mgr_patron), 'pref ON: manager sees multi AB' );
    ok( $r_no->can_access($mgr_patron), 'pref ON: manager sees no limits' );

    # Superlibrarian bypass (branch A)
    ok( $r_A->can_access($super_patron),  'pref ON: super sees limited A' );
    ok( $r_B->can_access($super_patron),  'pref ON: super sees limited B' );
    ok( $r_AB->can_access($super_patron), 'pref ON: super sees multi AB' );

    # Preference OFF (everything accessible, manage disabled)
    t::lib::Mocks::mock_preference( 'LimitReportsByBranch', 0 );
    ok( !Koha::Report->can_manage_limits($super_patron), 'pref OFF: super cannot manage limits' );
    ok( !Koha::Report->can_manage_limits($mgr_patron),   'pref OFF: manager cannot manage limits' );
    ok( !Koha::Report->can_manage_limits($basic_patron), 'pref OFF: basic cannot manage limits' );
    ok( $r_B->can_access($basic_patron),                 'pref OFF: limited excludes branch still accessible' );
    ok( $r_A->can_access($basic_patron),                 'pref OFF: limited includes branch accessible' );
    ok( $r_AB->can_access($basic_patron),                'pref OFF: multi-limit accessible' );
    ok( $r_no->can_access($basic_patron),                'pref OFF: no limits accessible' );
};

$schema->storage->txn_rollback;
