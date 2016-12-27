<?php
#
# Concierge for Hackerspace Brussels - Web front-end
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

try 
{
    $MissingUsrText=""; 
    $MissingPwText="";
    $dbh = new PDO ("mysql:host=". $CONFIG['dbhostname'] . ";dbname=" . $CONFIG['mydb'] . ";charset=UTF8", $CONFIG['dbuser'], $CONFIG['dbpass']);
    $dbh->setAttribute (PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    $dbh->setAttribute (PDO::ATTR_EMULATE_PREPARES, false);
    $stmt = $dbh->prepare ("select id, passwordhash from person where nickname = :nickname limit 1", array(PDO::ATTR_CURSOR => PDO::CURSOR_FWDONLY));

    // Validate credentials...
    if ( ($_SERVER['REQUEST_METHOD'] == "POST") and ($_REQUEST['user'] != "") and ($_REQUEST['pass'] != "") )
	{
	    $stmt->execute( array (':nickname' => $SANITIZED_REQUEST['user'] ) );
	    $result = $stmt->fetchAll();

	    if ( $stmt->rowcount() == 1 )
	    { // The user exist. Check password...
		if (password_verify ( $_REQUEST['pass'],$result[0]['passwordhash'] ) )
		{ // Good password: set person ID into session
		    $_SESSION['person_ID'] = $result[0]['id'];
		} else 
		{
		    $MissingPwText="Invalid credentials"; // Bad password
		}
	    } else
	    {
		$MissingPwText="Invalid credentials"; // Specified user does not exist
	    }
	}
    $dbh = null;
}
catch (PDOException $e) 
{
    html_header ('FAIL');
    printf ("<H1>Database failed: %s</H1><br />\n", $e->GetMessage());
    die;
}

### Processing done. Act on/display the results
if (isset($_SESSION['person_ID']))
    { // Authenticated bit
	if ( isset ($_SESSION['redirect']))
	{
	    header ('Location: ' . $_SESSION['redirect']); // Redirect to caller script
	} else 
	    header ("Location: user_dashboard.php"); // Redirect to user dashboard page if we were not redirected
    } else
    { // Non-authenticated bit: show login page
	html_header ('Hello');
	if ( ($_SERVER['REQUEST_METHOD'] == "POST") and ($_REQUEST['user'] == "") ) $MissingUsrText="Field cannot be empty" ;
	if ( ($_SERVER['REQUEST_METHOD'] == "POST") and ($_REQUEST['pass'] == "") ) $MissingPwText="Field cannot be empty" ;
	printf (" <H1>%s Members Login Form</H1>\n", $CONFIG['CAorgname']);
	printf (" <FORM Method=\"POST\" Action=\"%s\">\n", $_SERVER['SCRIPT_NAME']);
	printf ("  Username: <INPUT type=\"text\" size=20 name=\"user\" value=\"%s\">%s<br />\n", $SANITIZED_REQUEST['user'], $MissingUsrText);
	printf ("  Password: <INPUT type=\"password\" size=20 name=\"pass\">%s<br />\n", $MissingPwText);
	printf (" <INPUT type=\"submit\" value=\"Login\">\n");
	printf (" </FORM>\n");
	printf ("<A HREF=\"forgotpassword.php\">Forgot password ?</A><BR />\n");
	printf ("<A HREF=\"newaccount.php\">Create new account</A><BR />\n");
    }
#dumpglobals();
?>
