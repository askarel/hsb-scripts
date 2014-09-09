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

$CONFIGFILE=dirname (__FILE__) . '/config.php';

# Load the common stuff
include_once('./lib/commonfunctions.php');

# Pre-sanitize all inputs
$_POST = sanitize_input ($_POST);

# Launch the setup script if the config file is not found
if (!file_exists($CONFIGFILE))
    {
	require('./lib/setup.php');
    } else
    {
# 	Load configuration options
	require_once ($CONFIGFILE);
# New member request
	if (isset ($_POST['newmember']))
	{
	    require ('./lib/newmember.php');
	} else
	{
	    require_once ('./lib/login.php');
        }
    }
html_footer();
?>
