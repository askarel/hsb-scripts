#!/bin/sh
#
#	The callback script
#
#	(c) 2014 Frederic Pasteleurs <frederic@askarel.be>
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# Sample script to illustrate the calling feature of the door controller
readonly ME="$(basename $0)"
readonly DBFILE="/var/tmp/rfidpoll.txt"

logger -t $ME "$# Command line parameter received: '$1' '$2' '$3'"

# Prepare the greeting depending of the time of the day
HOUR="$(date '+%H')"
test "$HOUR" -ge 12 -a "$HOUR" -lt 18 && GREETING="Good afternoon"
test "$HOUR" -ge 18 -a "$HOUR" -le 23 && GREETING="Good evening"
test "$HOUR" -ge 6 -a "$HOUR" -lt 12 && GREETING="Good morning"
test "$HOUR" -ge 0 -a "$HOUR" -lt 6 && GREETING="Good night"

speakup()
{
#    test -x /home/pi/troll-remote && /home/pi/troll-remote speak "$1"
    test -x "$(which flite)" && flite -t "$1"
}

case "$1" in
    "26")
	true
	;;
    "40")
	# opened door from inside with button
	wget -q -O - "http://127.0.0.1:8080/api/notify/door/open" > /dev/null
	speakup "$2"
	;;
    "43")
	# opened door from system (card / webinterface)
	wget -q -O - "http://127.0.0.1:8080/api/notify/door/open" > /dev/null
        CARDHASH="$(echo "$3"| cut -d ' ' -f 3)"
        DESC="$(echo "$3"| cut -d ' ' -f 2)"
        echo "$3"| read DESC CARDHASH
	if [ "$DESC" = "tag" ]; then
	    RES="$(test -f "$DBFILE" && cat "$DBFILE"| awk "\$1 == \"$CARDHASH\""|cut -f 6)"
	    sleep 15
	    case "$RES" in
	    "") 
		speakup "who are you"
		;;
	    "landlord")
		speakup "The landlord is coming in. Hide."
		;;
	    *)
		speakup "$GREETING $RES"
		;;
	    esac
	else
	    speakup "$2"
	fi

	;;
    "44")
	# door bell rang
	wget -q -O - "http://127.0.0.1:8080/api/notify/bell" > /dev/null 
	speakup "$2"
	;;
    *)
	speakup "$2"
	;;
esac
