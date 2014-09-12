<?
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

# First thing first: it's a modern script supposed to be used on
# decent browsers.
header ('Content-type: text/html; charset=utf8');
# Start a new session or open an existing one
session_start();

$CONFIGFILE=dirname (__FILE__) . '/config.php';

# Load the common stuff
include_once('./lib/commonfunctions.php');
require_once('./lib/password.php');

# Pre-sanitize all inputs
$SANITIZED_POST = sanitize_input ($_POST);

# Launch the setup script if the config file is not found
if (!file_exists($CONFIGFILE))
    {
	require('./lib/setup.php');
    } else
    {
# 	Load configuration options
	require_once ($CONFIGFILE);
	try 
	{
	    $dbh = new PDO ("mysql:host=". $CONFIG['dbhostname'] . ";dbname=" . $CONFIG['mydb'] . ";charset=UTF8", $CONFIG['dbuser'], $CONFIG['dbpass']);
	    $dbh->setAttribute (PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
	    $dbh->setAttribute (PDO::ATTR_EMULATE_PREPARES, false);

	    if (isset ($SANITIZED_POST['newmember'])) // New member ?
	    {
		require ('./lib/newmember.php');
	    } else
	    {
		if (isset ($_SESSION['MemberID'])) // Logged in ?
		{
		    printf ("Logged in as user '%s'<br />\n", $_SESSION['hsbuser']);
		} else
		{
		    require_once ('./lib/login.php');
		}
	    }
	    $dbh = null;
	}
	catch (PDOException $e) 
	{
	    html_header ('FAIL');
	    printf ("<H1>Database failed: %s</H1><br />\n", $e->GetMessage());
	}
    }
dumparray ($_SESSION, '$_SESSION');
html_footer();
?>
