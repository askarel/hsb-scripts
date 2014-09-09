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

# Is there a user name ?
if (isset ($_POST['hsbuser']))
    {
	if ($_POST['hsbuser'] == '')
	    {
		$MissingUsrText = '<font color="red">Username is required</font>';
	    }
    } else
    {
	$MissingUsrText = '';
    }

# Is there a password ?
if (isset ($_POST['hsbpass']))
    {
	if (($_POST['hsbpass'] == '') and (!isset ($_POST['lostpw'])))
	    {
		$MissingPwText = '<font color="red">Password is required</font>';
	    }
    } else
    {
	$MissingPwText = '';
    }

# Process password reset (TODO)

# Check password and set cookie (TODO)


html_header ('Login');
printf (" <H1>%s Members Login Form</H1>\n", $CONFIG['orgname']);
printf (" <FORM Method=\"POST\" Action=\"%s\">\n", $_SERVER['SCRIPT_NAME']);
printf ("  Username: <INPUT type=\"text\" size=20 name=\"hsbuser\" value=\"%s\">%s<br />\n", $_POST['hsbuser'], $MissingUsrText);
printf ("  Password: <INPUT type=\"password\" size=20 name=\"hsbpass\">%s<br />\n", $MissingPwText);
printf (" <INPUT type=\"submit\" value=\"Login\">\n");
printf (" <INPUT TYPE=\"submit\" name=\"lostpw\" value=\"lost password ?\"><br />");
printf (" <INPUT TYPE=\"submit\" name=\"newmember\" value=\"Become a member here\"><br />");
printf (" </FORM>\n");
#dumparray ($_SERVER, '$_SERVER');
dumparray ($_POST, '$_POST');
?>
