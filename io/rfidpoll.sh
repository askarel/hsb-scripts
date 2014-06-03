#!/bin/sh

ME=$(basename $0)
PAUSEFILE="/tmp/RFID.register"
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

    ./blackknightio beep "RFID tag seen. Hash: $CARDHASH"

    RES=`mysql -u rfid_shell_user -p'ChangeMe' --skip-column-names -B -e "call rfid_db_hsbxl.checktag('"$CARDHASH"');" rfid_db_hsbxl`
    if [ -n "$RES" ]; then
      ./blackknightio open "tag $CARDHASH"
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
