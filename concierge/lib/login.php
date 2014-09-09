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

html_header ('Login');
printf (" <H1>%s Members Login Form</H1>\n", $CONFIG['orgname']);
printf (" <FORM Method=\"POST\" Action=\"%s\">\n", $_SERVER['SCRIPT_NAME']);
printf ("  Username: <INPUT type=\"text\" size=20 name=\"hsbuser\" value=\"%s\"><br />\n", "");
printf ("  Password: <INPUT type=\"password\" size=20 name=\"hsbpass\"><br />\n");
printf (" <INPUT type=\"submit\" value=\"Login\">\n");
printf (" </FORM>\n");
printf (" Lost your password ? <A HREF=\"%s?ACTION=lostpw\">Recover account.</A><br />\n", $_SERVER['SCRIPT_NAME']);
printf (" Not a member ? <A HREF=\"%s?ACTION=apply\">Apply here.</A><br />\n", $_SERVER['SCRIPT_NAME']);
dumparray ($_SERVER, '$_SERVER');
dumparray ($_POST, '$_POST');
?>
