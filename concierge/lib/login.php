<?
#
# Concierge for Hackerspace Brussels - Web front-end - login form
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


# redirect to main page
if ( !isset ($CONFIGFILE))
{
    header ('Status: 301 Moved Permanently', false, 301);
    header ('Location: ../index.php');
    exit;
}

$MissingPwText = '';
$MissingUsrText = '';

# Is there a user name ?
if (isset ($SANITIZED_POST['hsbuser']) and ($SANITIZED_POST['hsbuser'] == ''))
    {
	$MissingUsrText = '<font color="red">Username is required</font>';
    } 

# Is there a password ?
if (isset ($SANITIZED_POST['hsbpass']) and ($SANITIZED_POST['hsbpass'] == '') and (!isset ($SANITIZED_POST['lostpw'])))
    {
	$MissingPwText = '<font color="red">Password is required</font>';
    }

# Process password reset (TODO)

# Check password and set session variable (TODO)

# Show login form
html_header ('Login');
printf (" <H1>%s Members Login Form</H1>\n", $CONFIG['orgname']);
printf (" <FORM Method=\"POST\" Action=\"%s\">\n", $_SERVER['SCRIPT_NAME']);
printf ("  Username: <INPUT type=\"text\" size=20 name=\"hsbuser\" value=\"%s\">%s<br />\n", $SANITIZED_POST['hsbuser'], $MissingUsrText);
printf ("  Password: <INPUT type=\"password\" size=20 name=\"hsbpass\">%s<br />\n", $MissingPwText);
printf (" <INPUT type=\"submit\" value=\"Login\">\n");
printf (" <INPUT TYPE=\"submit\" name=\"lostpw\" value=\"lost password ?\"><br />");
printf (" <INPUT TYPE=\"submit\" name=\"newmember\" value=\"Become a member here\"><br />");
printf (" </FORM>\n");

#printf ("%s<br />\n", password_hash ($SANITIZED_POST['hsbpass'], PASSWORD_DEFAULT) );
#dumparray ($_SERVER, '$_SERVER');
dumparray ($SANITIZED_POST, '$SANITIZED_POST');
?>
