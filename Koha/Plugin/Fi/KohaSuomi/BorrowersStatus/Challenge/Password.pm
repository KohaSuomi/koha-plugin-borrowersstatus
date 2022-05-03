package Koha::Plugin::Fi::KohaSuomi::BorrowersStatus::Challenge::Password;

# Copyright 2015 Vaara-kirjastot
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

use Koha::Patrons;
use Koha::AuthUtils;
use File::Basename;
use Fcntl qw/O_RDONLY/; # O_RDONLY is used in generate_salt
use Crypt::Eksblowfish::Bcrypt qw(bcrypt en_base64);

use base qw(Koha::Plugin::Fi::KohaSuomi::BorrowersStatus::Challenge);


use Encode qw( encode is_utf8 );

use Koha::Patron;

use base 'Exporter';

my $CONFPATH = dirname($ENV{'KOHA_CONF'});

our @usernameAliasColumns = ('userid', 'cardnumber'); #Possible columns to treat as the username when authenticating. Must be UNIQUE in DB.

=head NAME Koha::Auth::Challenge::Password

=head SYNOPSIS

This module implements the more specific behaviour of the password authentication component.

=cut

=head challenge
STATIC

    Koha::Auth::Challenge::Password::challenge();

@RETURN Koha::Patron-object if check succeedes, otherwise throws exceptions.
@THROWS Koha::Exception::LoginFailed from Koha::AuthUtils password checks.
=cut

# Initialize Logger
my $log_conf = $CONFPATH . "/log4perl.conf";
Log::Log4perl::init($log_conf);
my $log = Log::Log4perl->get_logger('api');

sub challenge {
    my ($userid, $password) = @_;
    
    my $borrower;
    if (C4::Context->config('useldapserver')) {
        $borrower = Koha::Plugin::Fi::KohaSuomi::BorrowersStatus::Challenge::Password::checkLDAPPassword($userid, $password);
        return $borrower if $borrower;
    }
    if (C4::Context->preference('casAuthentication')) {
        $log->warn("Koha::Auth doesn't support CAS-authentication yet. Please refactor the CAS client implementation to work with Koha::Auth. It cant be too hard :)");
    }
    if (C4::Context->config('useshibboleth')) {
        $log->warn("Koha::Auth doesn't support Shibboleth-authentication yet. Please refactor the Shibboleth client implementation to work with Koha::Auth. It cant be too hard :)");
    }

    return Koha::Plugin::Fi::KohaSuomi::BorrowersStatus::Challenge::Password::checkKohaPassword($userid, $password);
}

=head checkKohaPassword

    my $borrower = Koha::Auth::Challenge::Password::checkKohaPassword($userid, $password);

Checks if the given username and password match anybody in the Koha DB
@PARAM1 String, user identifier, either the koha.borrowers.userid, or koha.borrowers.cardnumber
@PARAM2 String, clear text password from the authenticating user
@RETURN Koha::Patron, if login succeeded.
                Sets Koha::Patron->isSuperuser() if the user is a superuser.
@THROWS Koha::Exception::LoginFailed, if no matching password was found for all username aliases in Koha.
=cut

sub checkKohaPassword {
    
    my ($userid, $password) = @_;
    my $borrower; #Find the borrower to return

    $borrower = checkKohaSuperuser($userid, $password);
    
    
    return $borrower if $borrower;

    my $usernameFound = 0; #Report to the user if userid/barcode was found, even if the login failed.
    #Check for each username alias if we can confirm a login with that.
    for my $unameAlias (@usernameAliasColumns) {
        my $borrower = Koha::Patrons->find({$unameAlias => $userid});
        if ( $borrower ) {
            $usernameFound = 1;
            return $borrower if ( checkHash( $password, $borrower->password ) );
        }
    }

    $log->warn ("Password authentication failed for the given ".( ($usernameFound) ? "password" : "username and password").".");
}

sub checkHash {
    my ( $password, $stored_hash ) = @_;

    $password = Encode::encode( 'UTF-8', $password )
            if Encode::is_utf8($password);

    return if $stored_hash eq '!';

    my $hash;
    if ( substr( $stored_hash, 0, 2 ) eq '$2' ) {
        $hash = hash_password( $password, $stored_hash );
    } else {
        #@DEPRECATED Digest::MD5, don't use it or you will get hurt.
        require Digest::MD5;
        $hash = Digest::MD5::md5_base64($password);
    }
    return $hash eq $stored_hash;
}

=head checkLDAPPassword

Checks if the given username and password match anybody in the LDAP service
@PARAM1 String, user identifier
@PARAM2 String, clear text password from the authenticating user
@RETURN Koha::Patron, or
            undef if we couldn't reliably contact the LDAP server so we should
            fallback to local Koha Password authentication.
@THROWS Koha::Exception::LoginFailed, if LDAP login failed
=cut

sub checkKohaSuperuser {
    my ($userid, $password) = @_;

        if ( $userid && $userid eq C4::Context->config('user') ) {
            if ( $password && $password eq C4::Context->config('pass') ) {
                return _createTemporarySuperuser();
        }
        else {
            $log->warn("Password authentication failed");
        }
    }
}

# Using Bcrypt method for hashing. This can be changed to something else in future, if needed.
sub hash_password {
    my $password = shift;
    $password = Encode::encode( 'UTF-8', $password )
      if Encode::is_utf8($password);

    # Generate a salt if one is not passed
    my $settings = shift;
    unless( defined $settings ){ # if there are no settings, we need to create a salt and append settings
    # Set the cost to 8 and append a NULL
        $settings = '$2a$08$'.en_base64(generate_salt('weak', 16));
    }
    # Encrypt it
    return bcrypt($password, $settings);
}

# the implementation of generate_salt is loosely based on Crypt::Random::Provider::File
sub generate_salt {
    # strength is 'strong' or 'weak'
    # length is number of bytes to read, positive integer
    my ($strength, $length) = @_;

    my $source;

    if( $length < 1 ){
        die "non-positive strength of '$strength' passed to Koha::AuthUtils::generate_salt\n";
    }

    if( $strength eq "strong" ){
        $source = '/dev/random'; # blocking
    } else {
        unless( $strength eq 'weak' ){
            warn "unsuppored strength of '$strength' passed to Koha::AuthUtils::generate_salt, defaulting to 'weak'\n";
        }
        $source = '/dev/urandom'; # non-blocking
    }

    sysopen SOURCE, $source, O_RDONLY
        or die "failed to open source '$source' in Koha::AuthUtils::generate_salt\n";

    # $bytes is the bytes just read
    # $string is the concatenation of all the bytes read so far
    my( $bytes, $string ) = ("", "");

    # keep reading until we have $length bytes in $strength
    while( length($string) < $length ){
        # return the number of bytes read, 0 (EOF), or -1 (ERROR)
        my $return = sysread SOURCE, $bytes, $length - length($string);

        # if no bytes were read, keep reading (if using /dev/random it is possible there was insufficient entropy so this may block)
        next unless $return;
        if( $return == -1 ){
            die "error while reading from $source in Koha::AuthUtils::generate_salt\n";
        }

        $string .= $bytes;
    }

    close SOURCE;
    return $string;
}

sub _createTemporarySuperuser {
    my $borrower = Koha::Patron->new();

    my $superuserName = C4::Context->config('user');
    $borrower->isSuperuser(1);
    $borrower->set({borrowernumber => 0,
                       userid     => $superuserName,
                       cardnumber => $superuserName,
                       firstname  => $superuserName,
                       surname    => $superuserName,
                       branchcode => 'NO_LIBRARY_SET',
                       email      => C4::Context->preference('KohaAdminEmailAddress')
                    });
    return $borrower;
}
    
sub checkLDAPPassword {
    my ($userid, $password) = @_;
    
    $log->debug("trying checkLDAPPassword");

    #Lazy load dependencies because somebody might never need them.
    require C4::Auth_with_ldap;

    my ($retval, $cardnumber, $local_userid) = C4::Auth_with_ldap::checkpw_ldap($userid, $password);    # EXTERNAL AUTH
    if ($retval == -1) {
        $log->warn("LDAP authentication failed for the given username and password");
    }

    if ($retval) {
        my $borrower = Koha::Patrons->find({userid => $local_userid});
        return $borrower;
    }
    return undef;
}

1;
