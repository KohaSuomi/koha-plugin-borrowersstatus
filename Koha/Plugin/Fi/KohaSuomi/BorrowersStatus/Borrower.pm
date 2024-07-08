package Koha::Plugin::Fi::KohaSuomi::BorrowersStatus::Borrower;

# This file is part of Koha.
#
# Koha is free software; you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software
# Foundation; either version 3 of the License, or (at your option) any later
# version.
#
# Koha is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with Koha; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

use Modern::Perl;
use utf8;

use Mojo::Base 'Mojolicious::Controller';
use Mojo::JSON;

use C4::Members;
use Koha::Patrons;
use Koha::Exceptions;

use Koha::Plugin::Fi::KohaSuomi::BorrowersStatus::Challenge::Password;
use Koha::Plugin::Fi::KohaSuomi::BorrowersStatus::Exceptions::Exceptions;
use Koha::Plugin::Fi::KohaSuomi::BorrowersStatus::Exceptions::Exception;

use Scalar::Util qw( blessed );
use Try::Tiny;
use File::Basename;
use POSIX qw(strftime);

#from Members.pm
our (@ISA,@EXPORT,@EXPORT_OK,$debug);

# NOTE
#
# This controller is for Koha-Suomi 3.16 ported operations. For new patron related
# endpoints, use /api/v1/patrons and Koha::REST::V1::Patron controller instead


########################################################################################################################

my $CONFPATH = dirname($ENV{'KOHA_CONF'});

# Initialize Logger
my $log_conf = $CONFPATH . "/log4perl.conf";
Log::Log4perl::init($log_conf);
my $log = Log::Log4perl->get_logger('api');
$log->debug("Received borrowers/status request");
sub status {
    my $c = shift->openapi->valid_input or return;

    my $username = $c->validation->param('uname');
    my $password = $c->validation->param('passwd');
    my ($borrower, $error, $patron, $payload);
    my $lastseen = strftime "%Y-%m-%d %H:%M:%S", localtime;
    
    if ( defined $username ){
        $patron = Koha::Patrons->find({ cardnumber => $username });
        $patron = Koha::Patrons->find({ userid => $username }) unless $patron;
    }
    
    if (!$patron) {
        return $c->render( status => 400, openapi => { error => 'Authentication failed for the given username and password.' } );
    }
    
    if ($patron->account_locked) {
        $patron->update({ login_attempts => $patron->login_attempts + 1 });
        $patron->store;
        return $c->render(
            status => 401, 
            openapi => { error => "Login failed." }
        );
    }        

    try {
        $borrower = Koha::Plugin::Fi::KohaSuomi::BorrowersStatus::Challenge::Password::challenge(
                $username,
                $password
        );

        my $kp = GetMember(userid=>$borrower->userid);
        my $flags = C4::Members::patronflags( $kp );
        my $fines_amount = $flags->{CHARGES}->{amount};
        $fines_amount = ($fines_amount and $fines_amount > 0) ? $fines_amount : 0;
        my $fee_limit = C4::Context->preference('noissuescharge') || 5;
        my $fine_blocked = $fines_amount > $fee_limit;
        my $card_lost = $kp->{lost} || $flags->{LOST};
        my $basic_privileges_ok = !$borrower->is_debarred && !$borrower->is_expired && !$fine_blocked;

        # KD-4344 Card might be in the wrong hands, throw an exception to block access.
        Koha::Plugin::Fi::KohaSuomi::BorrowersStatus::Exceptions::Exception::LoginFailed->throw() if ( ( $patron and $patron->account_locked ) or $card_lost );

        for (qw(EXPIRED CHARGES CREDITS GNA LOST DBARRED NOTES)) {
                ($flags->{$_}) or next;
                if ($flags->{$_}->{noissues}) {
                        $basic_privileges_ok = 0;
                }
        }

        $payload = {
            borrowernumber => 0+$borrower->borrowernumber,
            cardnumber     => $borrower->cardnumber || '',
            surname        => $borrower->surname || '',
            firstname      => $borrower->firstname || '',
            age            =>  $borrower->get_age || 0,
            email            =>  $borrower->email || '',
            homebranch     => $borrower->branchcode || '',
            fines          => $fines_amount+0,
            language       => 'fin' || '',
            charge_privileges_denied    => _bool(!$basic_privileges_ok),
            renewal_privileges_denied   => _bool(!$basic_privileges_ok),
            recall_privileges_denied    => _bool(!$basic_privileges_ok),
            hold_privileges_denied      => _bool(!$basic_privileges_ok),
            card_reported_lost          => _bool($card_lost),
            too_many_items_charged      => _bool(0),
            too_many_items_overdue      => _bool(0),
            too_many_renewals           => _bool(0),
            too_many_claims_of_items_returned => _bool(0),
            too_many_items_lost         => _bool(0),
            excessive_outstanding_fines => _bool($fine_blocked),
            recall_overdue              => _bool(0),
            too_many_items_billed       => _bool(0),
        };

        # KD-4344 Reset failed login attempts on succesfull login
        if ( $patron ) {
            $patron->update({ login_attempts => 0 });
            $patron->update({ lastseen => $lastseen });
            $patron->store;
        }

        return $c->render( status => 200, openapi => $payload );
    } catch {
        
        # KD-4344 Update the amount of failed login attempts
        if ( $patron ) {
            $log->debug("Updating login_attempts for ". $patron->borrowernumber .".");
            $patron->update({ login_attempts => $patron->login_attempts + 1 });
            $patron->store;
        }
        # KD-4344 Generic error message instead of $_->error so as not to reveal anything about our user ids.
        return $c->render( status => 400, openapi => { error => 'Authentication failed for the given username and password.' } );
    };
}

sub _bool {
    return $_[0] ? Mojo::JSON->true : Mojo::JSON->false;
}

sub GetMember {
    my ( %information ) = @_;
    if (exists $information{borrowernumber} && !defined $information{borrowernumber}) {
        #passing mysql's kohaadmin?? Makes no sense as a query
        return;
    }
    my $dbh = C4::Context->dbh;
    my $select =
    q{SELECT borrowers.*, categories.category_type, categories.description
    FROM borrowers 
    LEFT JOIN categories on borrowers.categorycode=categories.categorycode WHERE };
    my $more_p = 0;
    my @values = ();
    for (keys %information ) {
        if ($more_p) {
            $select .= ' AND ';
        }
        else {
            $more_p++;
        }

        if (defined $information{$_}) {
            $select .= "$_ = ?";
            push @values, $information{$_};
        }
        else {
            $select .= "$_ IS NULL";
        }
    }
    $debug && warn $select, " ",values %information;
    my $sth = $dbh->prepare("$select");
    $sth->execute(@values);
    my $data = $sth->fetchall_arrayref({});
    #FIXME interface to this routine now allows generation of a result set
    #so whole array should be returned but bowhere in the current code expects this
    if (@{$data} ) {
        return $data->[0];
    }

    return;
}

1;
