#!/bin/sh


# door bell rang
test "$1" = "44" && wget -q -O - "http://127.0.0.1:8080/api/notify/bell" > /dev/null 

# opened door from inside with button
test "$1" = "40" && wget -q -O - "http://127.0.0.1:8080/api/notify/door/open" > /dev/null

# opened door from system (card / webinterface)
test "$1" = "43" && wget -q -O - "http://127.0.0.1:8080/api/notify/door/open" > /dev/null


# Sample script to illustrate the calling feature of the door controller

ME="$(basename $0)"

logger -t $ME "$# Command line parameter received: '$1' '$2' '$3'"

#test -x /home/pi/troll-remote && /home/pi/troll-remote speak "$2"

test -x "$(which flite)" && flite -t "$2"
