#
#  ----------------------------------------------------
#  httpry - HTTP logging and information retrieval tool
#  ----------------------------------------------------
#
#  Copyright (c) 2005-2009 Jason Bittel <jason.bittel@gmail.com>
#

package db_dump;

use warnings;
use DBI;

# -----------------------------------------------------------------------------
# GLOBAL VARIABLES
# -----------------------------------------------------------------------------
my $dbh;

# -----------------------------------------------------------------------------
# Plugin core
# -----------------------------------------------------------------------------

&main::register_plugin();

sub new {
        return bless {};
}

sub init {
        my $self = shift;
        my $cfg_dir = shift;
        my $sql;
        my $limit;

        &load_config($cfg_dir);

        $dbh = &connect_db($type, $db, $host, $port, $user, $pass);

        # Delete data inserted $rmbefore days prior
        if ($rmbefore > 0) {
                my ($year, $mon, $day, $hour, $min, $sec) = (localtime(time-(86400*$rmbefore)))[5,4,3,2,1,0];
                $limit = ($year+1900) . "-" . ($mon+1) . "-$day $hour:$min:$sec";

                $sql = qq{ DELETE FROM client_data WHERE timestamp < '$limit' };
                &execute_query($dbh, $sql);
                
                $sql = qq{ DELETE FROM server_data WHERE timestamp < '$limit' };
                &execute_query($dbh, $sql);
        }

        return;
}

sub list {
        return ('direction', 'timestamp', 'source-ip', 'dest-ip');
}

sub main {
        my $self = shift;
        my $record = shift;
        my $sql = "";
        my ($year, $mon, $day, $hour, $min, $sec) = (localtime)[5,4,3,2,1,0];
        my $now = ($year+1900) . "-" . ($mon+1) . "-$day $hour:$min:$sec";
        my $timestamp;
        my $request_uri;
 
        if ($record->{"direction"} eq '>') {
                return unless exists $record->{"host"};
                return unless exists $record->{"request-uri"};

                $sql = qq{ INSERT INTO client_data (timestamp, pktstamp, src_ip, dst_ip, hostname, uri)
                           VALUES ('$now', '$record->{"timestamp"}', '$record->{"source-ip"}', '$record->{"dest-ip"}',
                           '$record->{"host"}', '$record->{"request-uri"}') };
        } elsif ($record->{"direction"} eq '<') {
                return unless exists $record->{"status-code"};
                return unless exists $record->{"reason-phrase"};

                $sql = qq{ INSERT INTO server_data (timestamp, pktstamp, src_ip, dst_ip, status_code, reason_phrase)
                           VALUES ('$now', '$record->{"timestamp"}', '$record->{"source-ip"}', '$record->{"dest-ip"}',
                           '$record->{"status-code"}', '$record->{"reason-phrase"}') };
        }

        &execute_query($dbh, $sql) if $sql;
        
        return;
}

sub end {
        &disconnect_db();

        return;
}

# -----------------------------------------------------------------------------
# Load config file and check for required options
# -----------------------------------------------------------------------------
sub load_config {
        my $cfg_dir = shift;

        # Load config file; by default in same directory as plugin
        if (-e "$cfg_dir/" . __PACKAGE__ . ".cfg") {
                require "$cfg_dir/" . __PACKAGE__ . ".cfg";
        } else {
                die "Error: No config file found\n";
        }

        # Check for required options and combinations
        if (!$type) {
                die "Error: No database type provided\n";
        }
        if (!$db) {
                die "Error: No database name provided\n";
        }
        if (!$host) {
                die "Error: No database hostname provided\n";
        }
        $port = '3306' unless ($port);

        return;
}

# -----------------------------------------------------------------------------
# Build connection to specified database
# -----------------------------------------------------------------------------
sub connect_db {
        my $type = shift;
        my $db = shift;
        my $host = shift;
        my $port = shift;
        my $user = shift;
        my $pass = shift;
        my $dbh;
        my $dsn;

        $dsn = "DBI:$type:$db";
        $dsn .= ":$host" if $host;
        $dsn .= ":$port" if $port;

        if ($dbh = DBI->connect($dsn, $user, $pass, { PrintError => 0, RaiseError => 0, AutoCommit => 1 })) {
                &execute_query($dbh, qq{ USE $db });
        } else {
                die "Error: Cannot connect to database: " . DBI->errstr . "\n";
        }

        return $dbh;
}

# -----------------------------------------------------------------------------
# Generalized SQL query execution sub
# -----------------------------------------------------------------------------
sub execute_query {
        my $dbh = shift;
        my $sql = shift;
        my $sth;

        $sth = $dbh->prepare($sql) or die "Error: Cannot prepare query: " . DBI->errstr . "\n";
        $sth->execute() or die "Error: Cannot execute query: " . DBI->errstr . "\n";

        return $sth;
}

# -----------------------------------------------------------------------------
# Terminate active database connection
# -----------------------------------------------------------------------------
sub disconnect_db {
        $dbh->disconnect;
}

1;
