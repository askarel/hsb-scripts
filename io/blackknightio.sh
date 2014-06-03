#!/bin/sh

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

# door bell rang
test "$1" = "44" && wget -q -O - "http://127.0.0.1:8080/api/notify/bell" > /dev/null 

# opened door from inside with button
test "$1" = "40" && wget -q -O - "http://127.0.0.1:8080/api/notify/door/open" > /dev/null

# opened door from system (card / webinterface)
test "$1" = "43" && wget -q -O - "http://127.0.0.1:8080/api/notify/door/open" > /dev/null


# Sample script to illustrate the calling feature of the door controller

ME="$(basename $0)"

logger -t $ME "$# Command line parameter received: '$1' '$2' '$3'"

if [ "$1" = "43" ]; then
    CARDHASH="$(echo "$3"| cut -d ' ' -f 3)"
    DESC="$(echo "$3"| cut -d ' ' -f 2)"
    echo "$3"| read DESC CARDHASH
    if [ "$DESC" = "tag" ]; then
	RES=`mysql -u rfid_shell_user -p'ChangeMe' --skip-column-names -B -e "call rfid_db_hsbxl.getuserfromtag('"$CARDHASH"');" rfid_db_hsbxl`
	case "$RES" in
#	"") 
#	    speakup "Intruder alert"
#	    ;;
	"landlord")
	    speakup "Hide, The landlord is coming in"
	    ;;
	*)
	    speakup "$GREETING $RES"
	    ;;
	esac
    else
	speakup "$2"
    fi
else
    speakup "$2"
fi


