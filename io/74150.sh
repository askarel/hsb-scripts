#!/bin/bash
#
#	Read input multiplexer from the shell
#
#	(c) 2013 Frederic Pasteleurs <frederic@askarel.be>
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

ME=$(basename $0)

# Pin 15: A address
AADDRESS="11"
# Pin 14: B address
BADDRESS="9"
# Pin 13: C address
CADDRESS="10"
# Pin 11: D address
DADDRESS="22"
# Pin 10: readout bit (WARNING: must be level-shifted)
READOUT="4"


die()
{
    echo "$ME: $1. Exit"
    if [ "_$2" = "_" ]; then
        exit 1
        else
        exit $2
    fi
}

# Parameter: GPIO pin to use
gpioexport()
{
    test -z "$1" && die "No pin specified"
    test -d "/sys/class/gpio/gpio$1" || echo "$1" > /sys/class/gpio/export
}

# Parameter 1: GPIO pin to change
# Parameter 2: direction ('in' or 'out')
gpiosetdir()
{
    test "$2" = "out" -o "$2" = "in" || die "Direction should be 'in' or 'out', not '$2'"
    test -e /sys/class/gpio/gpio$1/direction || die "GPIO pin $1 not exported"
    echo "$2" > /sys/class/gpio/gpio$1/direction
}

# Parameter 1: GPIO pin to read
# Return: Pin value (1 or 0)
gpioread()
{
    test -e /sys/class/gpio/gpio$1/value || die "Cannot read GPIO pin. Did you export it ?"
    cat /sys/class/gpio/gpio$1/value
}

# parameter 1: GPIO pin to set
# parameter 2: value (1 or 0)
gpiowrite()
{
    test -e /sys/class/gpio/gpio$1/value || die "Cannot write GPIO pin. Did you export it ?"
    test "$2" = "1" -o "$2" = "0" || die "Pin value should be '1' or '0', not '$2'"
    echo "$2" > /sys/class/gpio/gpio$1/value
}

gpioexport $AADDRESS
gpioexport $BADDRESS
gpioexport $CADDRESS
gpioexport $DADDRESS
gpioexport $READOUT
gpiosetdir $AADDRESS out
gpiosetdir $BADDRESS out
gpiosetdir $CADDRESS out
gpiosetdir $DADDRESS out
gpiosetdir $READOUT in


# Read the word at the input on the 74150 chip
# The pins are active low, the output will reflect the state of the inputs
# Parameter 1: Address A pin
# Parameter 2: Address B pin
# Parameter 3: Address C pin
# Parameter 4: Address D pin
# Parameter 5: Input pin
read74150()
{
    for i in $(seq 0 0xf); do
	test -z "$GPIOWORD" && GPIOWORD=0
        gpiowrite $1 $(( ( ( $i >> 1 ) ^ $i ) & 1 ))
        gpiowrite $2 $(( ( ( $i >> 1 ) ^ $i ) >> 1 & 1 ))
        gpiowrite $3 $(( ( ( $i >> 1 ) ^ $i ) >> 2 & 1 ))
        gpiowrite $4 $(( ( ( $i >> 1 ) ^ $i ) >> 3 & 1 ))
#	GPIOVAL=$(gpioread $READOUT)
        GPIOWORD=$(( ( $GPIOWORD |   $(gpioread $5 ) << ( ( $i >> 1 ) ^ $i )  ) ))
#	echo "$(( $i >> 3 & 1 ))$(( $i >>  2 & 1 ))$(( $i >> 1 & 1 ))$(( $i & 1 )) 2^$i $GPIOVAL $(( $GPIOVAL << $i ))"
#	sleep 1
    done
    echo "$GPIOWORD"
}

read74150 $AADDRESS $BADDRESS $CADDRESS $DADDRESS $READOUT

