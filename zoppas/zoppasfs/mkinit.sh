#!/bin/sh

SERVERPUSH="root@gate:/srv/tftp/zoppas/"

if [ "$(pwd)" = "/" ]; then
    echo "I will not read from there !!"
    exit 1
fi

INITRD=$(basename $(pwd))
sync; find . | cpio -o -H newc | gzip -9 > ../$INITRD.gz

test -n "$SERVERPUSH" && scp "../$INITRD.gz" "$SERVERPUSH"


