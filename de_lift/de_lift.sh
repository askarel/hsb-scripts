#!/bin/bash
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
readonly DBFILE="/var/local/rfidpoll.txt"
readonly GARBAGE_WHITE_BLUE="Garbage day: Please take out the white and blue garbage bags."
readonly GARBAGE_WHITE_YELLOW="Garbage day: Please take out the white garbage bags and cardboard boxes."
readonly TROLLURL="http://hal9000.space.hackerspace.be/cgi-bin/sounds.sh"

RANDOM_BLOB="RANDOM_BLOB=$(dd if=/dev/urandom bs=112 count=1 2>/dev/null |base64 -w 0)"

logger -t $ME "$# Command line parameter received: '$1' '$2' '$3'"


# Prepare the greeting depending of the time of the day
HOUR="$(date '+%H')"
DAY="$(date '+%u')"
WEEKNR="$(date '+%U')"

test "$HOUR" -ge 12 -a "$HOUR" -lt 18 && GREETING="Good afternoon"
test "$HOUR" -ge 18 -a "$HOUR" -le 23 && GREETING="Good evening"
test "$HOUR" -ge 6 -a "$HOUR" -lt 12 && GREETING="Good morning"
test "$HOUR" -ge 0 -a "$HOUR" -lt 6 && GREETING="Good night"

# Garbage day announcement: only on mondays after 18:00 and until midnight;
GARBAGE=''
test "$HOUR" -ge 18 -a "$DAY" -eq 3 -a $(( $WEEKNR % 2 )) -ne 0 && GARBAGE=". $GARBAGE_WHITE_YELLOW"
test "$HOUR" -ge 18 -a "$DAY" -eq 3 -a $(( $WEEKNR % 2 )) -eq 0 && GARBAGE=". $GARBAGE_WHITE_BLUE"

speakup()
{
    test -x /home/pi/troll-remote && /home/pi/troll-remote speak "$1"
#    test -x "$(which flite)" && flite -t "$1"
    test -x "$(which espeak)" && espeak -s 120 "$1"
}

remote_speakup()
{
	wget -q -O - --content-disposition "$TROLLURL" --post-data="SPEAK=$1" > /dev/null 
}

case "$1" in
    "26")
	true
	;;
    "40")
	# opened door from inside with button
	wget -q -O - "http://127.0.0.1:8080/api/notify/door/open" > /dev/null
	speakup "$2$GARBAGE"
	;;
    "MSG_ELEVATOR_CMDLINE")
	# opened door from system (card / webinterface)
#	wget -q -O - "http://127.0.0.1:8080/api/notify/door/open" > /dev/null
        CARDHASH="$(echo "$3"| cut -d ' ' -f 3)"
        DESC="$(echo "$3"| cut -d ' ' -f 2)"
        echo "$3"| read DESC CARDHASH
	case "$DESC" in
	    "tag")
		RES="$(test -f "$DBFILE" && cat "$DBFILE"| awk "\$1 == \"$CARDHASH\""|cut -f 6)"
		case "$RES" in
		    "") 
			speakup "who are you"
		    ;;
		    *)
			speakup "$GREETING $RES, we're going up.$GARBAGE"
			remote_speakup "$RES is coming up.$GARBAGE" &
		    ;;
		esac
		;;
	    *)
		speakup "$2"
	    ;;
	esac
	;;
    "MSG_TUESDAY_ACTIVE_TAG")
        CARDHASH="$(echo "$3"| cut -d ' ' -f 3)"
        DESC="$(echo "$3"| cut -d ' ' -f 2)"
        echo "$3"| read DESC CARDHASH
	case "$DESC" in
	    "tag")
		RES="$(test -f "$DBFILE" && cat "$DBFILE"| awk "\$1 == \"$CARDHASH\""|cut -f 6)"
		case "$RES" in
		    "") 
			speakup "who are you"
		    ;;
		    *)
			speakup "$GREETING $RES, we're going up. Tuesday mode activated.$GARBAGE"
			remote_speakup "$RES is coming up and has activated tuesday mode.$GARBAGE" &
		    ;;
		esac
		;;
	    *)
		speakup "$2"
	    ;;
	esac
	
	;;
    "MSG_TUESDAY_CALL")
	speakup "Welcome to Hackerspace Brussels. I'm taking you to the 4th floor."
	remote_speakup "Clean your mess: We have a visitor coming up." &
	;;
    "MSG_TUESDAY_TIMEOUT")
	remote_speakup "Tuesday mode timeout." &
	;;
    "MSG_TUESDAY_ACTIVE_CMDLINE")
	remote_speakup "Tuesday mode activated." &
	;;
    "MSG_TUESDAY_FORCE_INACTIVE")
	speakup "Tuesday mode cancelled"
	remote_speakup "Tuesday mode cancelled from elevator." &
	;;
    "MSG_BUTTON_PUSHED")
	remote_speakup "Ding Dong." &
#	speakup "Ding Dong"
	;;
    "MSG_BOX_TAMPER")
	remote_speakup "ALERT: Elevator box is being tampered." &
	speakup "What are you doing ?"
	;;
    "MSG_BOX_RECLOSED")
	remote_speakup "ALERT: Elevator box has been re-closed." &
	;;
    *)
	speakup "$2"
	;;
esac

# Send UDP packet storm to HAL9000 with the current event (just in case TCP is not possible due to bad WiFi)
for i in $(seq 100); do echo -e "COMMAND=$1&$RANDOM_BLOB" > /dev/udp/2001:6f8:147f:4:21d:60ff:fe35:df19/54321; sleep 0.2; done
