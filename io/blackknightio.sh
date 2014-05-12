#!/bin/sh

# Sample script to illustrate the calling feature of the door controller

ME="$(basename $0)"

logger -t $ME "$# Command line parameter received: '$1' '$2' '$3'"

test -x "$(which flite)" && flite -t "$2 $3"
