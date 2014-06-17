#!/bin/bash
#
#	The RFID scanner
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

readonly ME=$(basename $0)
readonly DBFILE="/var/tmp/rfidpoll.txt"
readonly AR_HASH=0
readonly AR_STARTTIME=1
readonly AR_ENDTIME=2
readonly AR_FLAGS=3
readonly AR_REVOKED=4
readonly AR_NICK=5
test -x ./blackknightio && BLACKKNIGHT="./blackknightio"
test -x /usr/local/bin/blackknightio && BLACKKNIGHT="/usr/local/bin/blackknightio"

cleanup()
{
    logger -t "$ME" "Bailing out."
    exit
} 

trap cleanup KILL TERM QUIT INT

logger -t "$ME" "Starting up."
#set -x

test -z "$(which scriptor)" && echo "Scriptor not found !" && exit 1

while true; do
  ATRHASH=$(echo "reset" | scriptor 2> /dev/null | tail -n 1 | md5sum | cut -d ' ' -f 1)
  if [ "$ATRHASH" != 'd41d8cd98f00b204e9800998ecf8427e' ] ; then # d41d8cd98f00b204e9800998ecf8427e is the empty string hash
   if [ "$CARDHASH" = '' ]; then
    # Ask the card UID and hash the result (i don't care about the garbage)
    UIDHASH="$(echo 'ffca000000'|scriptor 2> /dev/null|tail -n 1 | md5sum | cut -d ' ' -f 1)"
    CARDHASH="$(echo -n "$UIDHASH $ATRHASH" | md5sum |cut -d ' ' -f 1)"
    logger -t "$ME" "Card scanned: hash: $CARDHASH"
    $BLACKKNIGHT beep "RFID tag seen. Hash: $CARDHASH" > /dev/null
    # If tag exist in file, fill array with data
    myhash=( $(test -f "$DBFILE" && cat "$DBFILE"| awk "\$1 == \"$CARDHASH\"") )
    test "$CARDHASH" != "${myhash[AR_HASH]}" && logger -t $ME "WARNING: UNKNOWN TAG: $CARDHASH"
    if [ "$CARDHASH" = "${myhash[AR_HASH]}" ]; then # Got hash ? Tell me more...
	if [ "$(date '+%s')" -ge "${myhash[AR_STARTTIME]}" ]; then # Is currentdate > startdate ?
	    if [ "${myhash[AR_REVOKED]}" = "0" ]; then # Is it revoked ?
		case "${myhash[AR_ENDTIME]}" in
		    "0"|"NULL") # End date is NULL or 0: card must be valid
			$BLACKKNIGHT open "tag $CARDHASH" > /dev/null
			;;
		    *) # There is an end date: check it
			test "$(date '+%s')" -le "${myhash[AR_ENDTIME]}" && $BLACKKNIGHT open "tag $CARDHASH" > /dev/null || logger -t "$ME" "Card ${myhash[AR_HASH]} is expired"
			;;
		esac
	    else
		logger -t $ME "Card ${myhash[AR_HASH]} is revoked !"
	    fi
	else
	    logger -t $ME "Card ${myhash[AR_HASH]} not yet valid"
	fi
    fi
   fi
  fi
  test "$ATRHASH" = 'd41d8cd98f00b204e9800998ecf8427e' && unset CARDHASH  # ATR has changed: card has disappeared
  unset ATRHASH
  sleep 0.5
done
