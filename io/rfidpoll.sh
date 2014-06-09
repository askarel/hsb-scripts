#!/bin/sh
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
readonly PAUSEFILE="/tmp/RFID.register"
readonly BLACKKNIGHT="./blackknightio"


cleanup()
{
    logger -t "$ME" "Bailing out."
    rm -f "$PAUSEFILE"
    echo
    exit
} 

trap cleanup KILL TERM QUIT INT


logger -t "$ME" "Starting up."
#set -x

# Kill pause file
rm -f $PAUSEFILE
test -z "$(which scriptor)" && echo "Scriptor not found !" && exit 1

while true; do
 if [ -f "$PAUSEFILE" ]; then
  logger -t $ME "Paused: about to add a user to the database"
  sleep 1
 else
  ATRHASH=$(echo "reset" | scriptor 2> /dev/null | tail -n 1 | md5sum | cut -d ' ' -f 1)
  if [ "$ATRHASH" != 'd41d8cd98f00b204e9800998ecf8427e' ] ; then # d41d8cd98f00b204e9800998ecf8427e is the empty string hash
   if [ "$CARDHASH" = '' ]; then
    # Ask the card UID and hash the result (i don't care about the garbage)
    UIDHASH="$(echo 'ffca000000'|scriptor 2> /dev/null|tail -n 1 | md5sum | cut -d ' ' -f 1)"
    CARDHASH="$(echo -n "$UIDHASH $ATRHASH" | md5sum |cut -d ' ' -f 1)"
    logger -t "$ME" "Card scanned: hash: $CARDHASH"

    $BLACKKNIGHT beep "RFID tag seen. Hash: $CARDHASH" > /dev/null

    RES=`mysql -u rfid_shell_user -p'ChangeMe' --skip-column-names -B -e "call rfid_db_hsbxl.checktag('"$CARDHASH"');" rfid_db_hsbxl`
    if [ -n "$RES" ]; then
      $BLACKKNIGHT open "tag $CARDHASH" > /dev/null
    else
     logger -t $ME "WARNING: UNKNOWN TAG: $CARDHASH"
    fi
   fi
  else
   unset CARDHASH
  fi
  unset ATRHASH
  sleep 0.5
 fi

done

