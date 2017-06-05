<?php
#
# Concierge for Hackerspace Brussels - Web front-end - Login page
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
$MissingUsrText=""; 
$MissingPwText="";

function login_page()
{
	html_header ('Hello');
	global $MissingUsrText, $MissingPwText, $CONFIG, $SANITIZED_REQUEST;
	if ( ($_SERVER['REQUEST_METHOD'] == "POST") and ($_REQUEST['user'] == "") ) $MissingUsrText="Field cannot be empty" ;
	if ( ($_SERVER['REQUEST_METHOD'] == "POST") and ($_REQUEST['pass'] == "") ) $MissingPwText="Field cannot be empty" ;
	printf ("<div>\n");
	printf (" <H1>%s Login Form</H1>\n",$CONFIG['CAorgname']);
	printf (" <FORM Method=\"POST\" Action=\"%s\">\n", $_SERVER['SCRIPT_NAME']);
	printf ("  Username: <INPUT type=\"text\" size=20 name=\"user\" value=\"%s\">%s<br />\n", $SANITIZED_REQUEST['user'], $MissingUsrText);
	printf ("  Password: <INPUT type=\"password\" size=20 name=\"pass\">%s<br />\n", $MissingPwText);
	printf (" <INPUT type=\"submit\" value=\"Login\">\n");
	printf (" </FORM>\n");
	printf ("<a HREF=\"forgotpassword.php\">Forgot password ?</a><br />\n");
	printf ("<a HREF=\"newaccount.php\">Create new account</a><br />\n");
	printf ("</div>\n");
}

// Validate supplied credentials...
if ( ($_SERVER['REQUEST_METHOD'] == "POST") and ($_REQUEST['user'] != "") and ($_REQUEST['pass'] != "") )
    {
	$rdn="uid=" . $SANITIZED_REQUEST['user'] . ",ou=" . $CONFIG['ldapuserou'] . "," . $CONFIG['ldapdn'];
	$resu=ldap_bind ($ldapconn, $rdn, $_REQUEST['pass']);
	if ($resu)
	    { // Bind operation is successful.
		$_SESSION['AUTH_RDN'] = $rdn; // Pass the RDN and the password to subsequent script
		$_SESSION['AUTH_RDN_PASS'] = $_REQUEST['pass'];
	    }
	    else
	    {
		$MissingPwText="Wrong credentials supplied.";
	    }
	// Debug
	//printf ("<br />rdn=%s<br />resu=%s<br />ldaperror=%s<br />\n", $rdn, $resu, ldap_error ($ldapconn));
    }

### Processing done. Act on/display the results
if (isset($_SESSION['AUTH_RDN']) and isset($_SESSION['AUTH_RDN_PASS']))
    { // Authenticated bit
	if ( isset ($_SESSION['redirect']))
	{
	    header ('Location: ' . $_SESSION['redirect']); // Redirect to caller script
	} else 
	    header ("Location: user_dashboard.php"); // Redirect to user dashboard page if we were not redirected
    } else
    { // Non-authenticated bit: show login page
	login_page();
    }
// dumpglobals();
?>
