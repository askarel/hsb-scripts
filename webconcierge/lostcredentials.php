<?php
#
# A simple LDAP password resetter
# (c) 2018 Frederic Pasteleurs <frederic@askarel.be>
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
include_once('./libaskarel.php');

static $CONFIG = array (
# LDAP parameters
	'ldaphost' => 'ldap.acme.invalid',
	'ldapport' => 389,
	'ldapdn' => 'dc=acme,dc=invalid',
	'ldapuserou' => 'users',
	'orgname' => 'ACME',
	'ldapbinddn' => 'uid=webconcierge,ou=services,dc=acme,dc=invalid',
	'ldapbindpw' => 'T0pS3cr3t'
);

# This will send the page end to the client
function html_footer()
{
    printf ("\n <p><A HREF=\"%s?startover=yes\">Click here</A> to start over<br />", $_SERVER['SCRIPT_NAME']);
    echo ("\n Powered by <A HREF=\"https://github.com/askarel/hsb-scripts/\">Askarel</A></p>\n </body>\n</html>\n");
}

function mainform($Message)
{
    global $CONFIG;
    html_header('hello');
    printf ("<div>\n");
    printf (" <H1>Get user name for %s</H1>\n",$CONFIG['orgname']);
    printf (" <FORM Method=\"POST\" Action=\"%s?action=getusername\">\n", $_SERVER['SCRIPT_NAME']);
    printf ("  Email address: <INPUT type=\"text\" size=20 name=\"emailaddress\">%s<br />\n", $Message['MissingEmailText1']);
    printf (" <INPUT type=\"submit\" value=\"Get user name\"><H3>%s</H3>\n", $Message['ButtonMessage1']);
    printf (" </FORM>\n");
    printf ("</div>\n");
    printf ("<div>\n");
    printf ("<hr>\n");
    printf (" <H1>Reset user password</H1>\n");
    printf (" <FORM Method=\"POST\" Action=\"%s?action=sendresettoken\">\n", $_SERVER['SCRIPT_NAME']);
    printf ("  Username: <INPUT type=\"text\" size=20 name=\"username\">%s<br />\n", $Message['MissingUserText']);
    printf ("  Email address: <INPUT type=\"text\" size=20 name=\"emailaddress\">%s<br />\n", $Message['MissingEmailText2']);
    printf (" <INPUT type=\"submit\" value=\"Reset password\"><H3>%s</H3>\n", $Message['ButtonMessage2']);
    printf (" </FORM>\n");
    printf ("</div>\n");
    printf ("<div>\n");
}

function tokenform($Message)
{
    html_header("Enter your reset token");
    printf ("<div>\n");
    printf (" <H1>Enter your reset token%s</H1><br />\n", $Message['creditdot']);
    printf (" A reset token has been sent to your e-mail address. Please check your mailbox and copy-paste the token into the field below<br />\n");
    printf (" WARNING: Do not close this window or leave this page: the reset token is tied to this specific browser session<br />\n");
    printf (" <FORM Method=\"POST\" Action=\"%s?action=submittoken\">\n", $_SERVER['SCRIPT_NAME']);
    printf ("  Reset token: <INPUT type=\"text\" size=40 name=\"resettoken\">%s<br />\n", $Message['tokenmsg']);
    printf (" <INPUT type=\"submit\" value=\"Send\">\n");
    printf (" </FORM>\n");
    printf ("</div>\n");
}

function newpass($Message)
{
    html_header("Enter your new password");
    printf ("<div>\n");
    printf (" <H1>Enter your new password</H1><br />\n");
    printf (" <FORM Method=\"POST\" Action=\"%s?action=dochange\">\n", $_SERVER['SCRIPT_NAME']);
    printf ("  New password: <INPUT type=\"password\" size=40 name=\"pwd1\">%s<br />\n", $Message['pwd1']);
    printf ("  Repeat password: <INPUT type=\"password\" size=40 name=\"pwd2\">%s<br />\n", $Message['pwd2']);
    printf (" <INPUT type=\"submit\" value=\"Change password\">\n");
    printf (" </FORM>\n");
    printf ("</div>\n");
}

// Taken from https://blog.michael.kuron-germany.de/2012/07/hashing-and-verifying-ldap-passwords-in-php/
function hash_password($password) // SSHA with random 4-character salt
{
    $salt = substr(str_shuffle(str_repeat('ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789',4)),0,4);
    return '{SSHA}' . base64_encode(sha1( $password.$salt, TRUE ). $salt);
}

# First thing first: it's a modern script (?) supposed to be used on
# decent browsers.
header ("Content-type: text/html; charset=utf8");
header ("X-Frame-Options: SAMEORIGIN");
// Automagically insert footer on exit
register_shutdown_function('html_footer');
session_start();

// Prepare LDAP connection
$ldapconn = ldap_connect ($CONFIG['ldaphost'], $CONFIG['ldapport']);
ldap_set_option($ldapconn, LDAP_OPT_PROTOCOL_VERSION, 3);
$ldapbind = ldap_bind($ldapconn, $CONFIG['ldapbinddn'], $CONFIG['ldapbindpw']); // LDAP credentials for script
$dataSubTree='ou=' . $CONFIG['ldapuserou'] . ',' . $CONFIG['ldapdn']; // Subtree where to search for user data
$ldapattributes = array ("mail", "uid", "givenname"); // Build LDAP attributes list to search
if (!$ldapbind) abort (sprintf ("LDAP failed: %s" , ldap_error($ldapconn)));

// Just in case someone wants to scrap everything and start over
if ( $_REQUEST['startover'] === 'yes') {
    $_SESSION['machinestate'] = '';
    $_SESSION['resettoken'] = '';
}

switch ($_SESSION['machinestate']) {
    case 'CHECK_MAINFORM_DATA': // Check default screen submitted data
	switch ($_SERVER['REQUEST_METHOD']) {
	    case 'POST':
		switch ($_REQUEST['action']) {
		    case 'getusername':
			if ( $_REQUEST['emailaddress'] === "" ) {
			    $mainformMSG['MissingEmailText1']="Field cannot be empty" ;
			    mainform($mainformMSG);
			} else { // Field was not empty: doing the lookup
			    $ldap_results = ldap_search ($ldapconn, $dataSubTree, "(" . $ldapattributes[0] . "=" . ldap_escape ($_REQUEST['emailaddress'], null, LDAP_ESCAPE_FILTER) . ")", $ldapattributes);
			    $ldap_entries = ldap_get_entries ($ldapconn, $ldap_results);
			    if ($ldap_entries['count'] > 0) { // More than zero ? We have data
				for ($i=0; $i<$ldap_entries['count']; $i++) {
				    $templatedata['uid'] = $templatedata['uid'] . $ldap_entries[$i][$ldapattributes[1]][0] . "\n";
				}
				$templatedata['orgname'] = $CONFIG['orgname'];
				$templatedata['mail'] = $ldap_entries[0]['mail'][0];
				if ( mail ( $ldap_entries[0]['mail'][0], "[" . $CONFIG['orgname'] . "] Username recovery", populatetemplate($_SERVER['SCRIPT_FILENAME'] . '_' . $_REQUEST['action'] . '.txt', $templatedata, null))) {
				    html_header('Success');
				    printf ("User name(s) successfully resent. Please check your mailbox");
				} else {
				    abort ("Mail sending failed");
				}
			    } else { // Zero results found: Just lie to the (ab)user
				html_header('Success');
				printf ("User name(s) successfully resent. Please check your mailbox."); // Hello Williams
			    }
			}
			break;
		    case 'sendresettoken':
			if ( $_REQUEST['emailaddress'] === "" )  $mainformMSG['MissingEmailText2']="Field cannot be empty" ;
			if ( $_REQUEST['username'] === "" )  $mainformMSG['MissingUserText']="Field cannot be empty" ;
			if ( ( $_REQUEST['username'] === "") or (  $_REQUEST['emailadress'] === "" ) )  {
			    mainform($mainformMSG);
			} else { // Fields were not empty: doing the lookup
			    // Search for the email address and the username in the LDAP
			    $ldap_results = ldap_search ($ldapconn, $dataSubTree, "(&(" . $ldapattributes[0] . "=" . ldap_escape ($_REQUEST['emailaddress'], null, LDAP_ESCAPE_FILTER) . ")(" . $ldapattributes[1] . "=" . ldap_escape ($_REQUEST['username'], null, LDAP_ESCAPE_FILTER) . "))", $ldapattributes);
			    $ldap_entries = ldap_get_entries ($ldapconn, $ldap_results);
			    switch ($ldap_entries['count'] ) {
				case 0:  // 0 entries found: Just lie to the (ab)user and clear the reset token.
				    $_SESSION['resettoken'] = '';
				    $ResetTokenMSG['creditdot']='.'; // Hello Williams
				    tokenform($ResetTokenMSG);
				    break;
				case 1: // 1 entry found: processing it
				    if ($_SESSION['resettoken'] === '') {
					$_SESSION['resettoken'] = randomstring (30);
					$_SESSION['userdn'] = $ldap_entries[0]['dn'];
					$templatedata['orgname'] = $CONFIG['orgname'];
					$templatedata['mail'] = $ldap_entries[0]['mail'][0];
					$templatedata['givenname'] = $ldap_entries[0]['givenname'][0];
					$templatedata['dn'] = $ldap_entries[0]['dn'];
					$templatedata['resettoken'] = $_SESSION['resettoken'];
					if ( ! mail ( $ldap_entries[0]['mail'][0], "[" . $CONFIG['orgname'] . "] Password reset token", populatetemplate($_SERVER['SCRIPT_FILENAME'] . '_' . $_REQUEST['action'] . '.txt', $templatedata, null))) {
					    abort ("Mail sending failed");
					} 
				    }
				    $_SESSION['machinestate'] = 'CHECK_SUBMITTED_TOKEN'; // Next step: validate the submitted token
				    tokenform($ResetTokenMSG);
				    break;
				default: // More than 1 is trouble !
				    abort ("Ambiguous query: STOP");
			    }
			}
			break;
		}
		break;
	    case 'GET': // Page reloaded: re-display the form
		if ( $_SESSION['resettoken'] === '') {
		    mainform($mainformMSG);
		} else {
		    tokenform($ResetTokenMSG);
		}
		break;
	    default: abort ("Invalid method: "  . $_SERVER['REQUEST_METHOD']);
	}
	break;
    case 'CHECK_SUBMITTED_TOKEN': // Check the submitted token
	switch ($_SERVER['REQUEST_METHOD']) {
	    case 'POST':
		if ( $_REQUEST['resettoken'] === '' ) { // Empty token field ?
		    $ResetTokenMSG['tokenmsg'] = "Token field should not be empty";
		    tokenform($ResetTokenMSG);
		} else {
		    if ( ! ( $_REQUEST['resettoken'] === $_SESSION['resettoken'] )) { // token error
			$ResetTokenMSG['tokenmsg'] = "Bad or expired token";
			tokenform($ResetTokenMSG);
		    } else { // Token match !
			$_SESSION['machinestate'] = 'CHECK_NEWPASS'; // Next step: validate the submitted passwords
			newpass($NewPassMSG);
		    }
		}
		break;
	    case 'GET':
		tokenform($ResetTokenMSG);
		break;
	    default: abort ("Invalid method: "  . $_SERVER['REQUEST_METHOD']);
	}
	break;
    case 'CHECK_NEWPASS': // Check the submitted passwords
	switch ($_SERVER['REQUEST_METHOD']) {
	    case 'POST':
		if ( ( $_REQUEST['pwd1'] === '' ) or ( $_REQUEST['pwd2'] === '' ) ) { // Empty password(s) ?
		    if ( $_REQUEST['pwd1'] === '' ) { $NewPassMSG['pwd1'] = "Field cannot be empty"; }
		    if ( $_REQUEST['pwd2'] === '' ) { $NewPassMSG['pwd2'] = "Field cannot be empty"; }
		    newpass($NewPassMSG);
		} else { // No empty password supplied. Check match...
		    if ( $_REQUEST['pwd1'] === $_REQUEST['pwd2'] ) { // Password match !
			$ldapentry['userPassword'] = hash_password($_REQUEST['pwd1']);
			if ( ldap_mod_add($ldapconn, $_SESSION['userdn'], $ldapentry) ) { // Successfully changed password !
			    $_SESSION['machinestate'] = '';
			    html_header ('SUCCESS');
			    die ("<H1>Password successfully changed.</H1><br />\n");
			    session_destroy;
			} else { // Password change failure
			    abort (sprintf ("LDAP failed: %s" , ldap_error($ldapconn)));
			}
		    } else { // No match
			$NewPassMSG['pwd2'] = "Password mismatch !";
			newpass($NewPassMSG);
		    }
		}
		break;
	    case 'GET':
		newpass($NewPassMSG);
		break;
	    default: abort ("Invalid method: "  . $_SERVER['REQUEST_METHOD']);
	}
	break;
    default: // Entry point: aka The default screen. Make sure we trash the reset token data
	$_SESSION['machinestate'] = 'CHECK_MAINFORM_DATA'; // Next step: validate submitted data
	$_SESSION['resettoken'] = '';
	mainform($mainformMSG);
}

# LDAP DEINIT CODE HERE
ldap_unbind ($ldapconn);
//dumpglobals();

?>