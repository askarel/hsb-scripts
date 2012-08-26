#!/bin/sh

# The rimshot CGI script - Trolling HSBXL with style
# (c) 2012 Frederic Pasteleurs <askarel@gmail.com>
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

DIR_AUDIOFILES="/srv/mpd/music/RIMSHOTS"
DIR_AUDIOFILES="./filez"
ME=$(basename $0)
METHODNAME="PLAY"
PLAYPROG="paplay"

cat << EOM
Content-type: text/html


<!DOCTYPE html>
<HTML>
 <HEAD>
  <TITLE>Rimshot and other shit</TITLE>
 </HEAD>
 <BODY>
  <H1>HSBXL TROLLING PAGE</H1>
EOM

if [ -d "$DIR_AUDIOFILES" ]; then
    echo "  <FORM ACTION=\"$ME\" method=\"GET\">"
    echo "   <P><INPUT TYPE=\"SUBMIT\" VALUE=\"RANDOM\" NAME=\"$METHODNAME\"></INPUT></P>"
    for i in $( ls -1 "$DIR_AUDIOFILES" ); do
	echo "   <INPUT TYPE=\"SUBMIT\" VALUE=\"$i\" NAME=\"$METHODNAME\"></INPUT>"
    done
    echo "  </FORM>"
fi

cat << EOM
 </BODY>
</HTML>
EOM

### Backend stuff
if [ "$( echo "$QUERY_STRING"|cut -d '=' -f 1 )" = "$METHODNAME" ]; then
    for i in $( ls -1 "$DIR_AUDIOFILES" ); do
	test "$i" = "$( echo "$QUERY_STRING"|cut -d '=' -f 2 )" && $PLAYPROG "$DIR_AUDIOFILES/$i" &
    done
	test "$( echo "$QUERY_STRING"|cut -d '=' -f 2 )" = "RANDOM" && $PLAYPROG "$DIR_AUDIOFILES/$(ls -1 "$DIR_AUDIOFILES" |shuf -n 1)" &
fi
