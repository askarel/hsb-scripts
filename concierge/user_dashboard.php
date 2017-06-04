<?php
#
# Concierge for Hackerspace Brussels - Web front-end - User dashboard
# (c) 2014 Frederic Pasteleurs <frederic@askarel.be>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; version 2 of the License.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program or from the site that you downloaded it
# from; if not, write to the Free Software Foundation, Inc., 59 Temple
# Place, Suite 330, Boston, MA  02111-1307   USA
#

# Load the common stuff (first thing)
include_once('./lib/commonfunctions.php');

function show_dashboard()
{
html_header ("Hello " . $_SESSION['AUTH_RDN']);
echo ("authenticated <br />");
printf ("<A HREF=\"%s?action=logout\">Log out user %s</A><BR />\n", $_SERVER['SCRIPT_NAME'], $_SESSION['AUTH_RDN'] );
}

# Redirect to index page if not already authenticated
if ( ! (isset($_SESSION['AUTH_RDN']) and isset($_SESSION['AUTH_RDN_PASS']) ) )
	{ // Non-Authenticated bit
	    $_SESSION['redirect'] = "user_dashboard.php";
	    header ("Location: index.php");
	    die;
	}

# Do some actions
switch ( $_REQUEST['action'] )
    {
	case "logout": // The logout link at the bottom
	    session_destroy();
	    header ("Location: index.php");
	    die;
	    break;
	default:
	    break;
    }

show_dashboard();

dumpglobals();

#dumparray ($persondata[0], 'persondata');
#try 
#{    // Load user data
#    $dbh = new PDO ("mysql:host=". $CONFIG['dbhostname'] . ";dbname=" . $CONFIG['mydb'] . ";charset=UTF8", $CONFIG['dbuser'], $CONFIG['dbpass']);
#    $dbh->setAttribute (PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
#    $dbh->setAttribute (PDO::ATTR_EMULATE_PREPARES, false);
#    $persondataRQ = $dbh->prepare ("select * from person where id = :id", array(PDO::ATTR_CURSOR => PDO::CURSOR_FWDONLY));
#    $persondataRQ->execute( array (':id' => $_SESSION['person_ID'] ) );
#    $persondata = $persondataRQ->fetchAll();
#    $personhistRQ = $dbh->prepare ("select * from person_history where member_id = :id", array(PDO::ATTR_CURSOR => PDO::CURSOR_FWDONLY));
#    $personhistRQ->execute( array (':id' => $_SESSION['person_ID'] ) );
#    $personhistory = $personhistRQ->fetchAll();
#
#    $dbh = null;
#}
#catch (PDOException $e) 
#{
#    html_header ('FAIL');
#    printf ("<H1>Database failed: %s</H1><br />\n", $e->GetMessage());
#}

?>
