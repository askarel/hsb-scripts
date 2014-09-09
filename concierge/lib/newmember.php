<?
#
# Concierge for Hackerspace Brussels - Web front-end - new member entry module
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
if (!isset($CONFIGFILE))
{
    header('Status: 301 Moved Permanently', false, 301);
    header('Location: ../index.php');
    exit;
}

html_header ('New member');

echo "new member entry module (STUB)";

?>