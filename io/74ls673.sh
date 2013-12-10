#!/bin/bash
#
#	Controlling shift register from the shell
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

# Pin 2: SHCLK
CLOCKPIN="7"
# Pin 5: STRCLK
STROBEPIN="8"
# Pin 6: SER pin
DATAPIN="25"

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
    echo "$1" > /sys/class/gpio/export
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

# parameter 1: strobe pin
# parameter 2: clock pin
# parameter 3: data pin
# parameter 4: word to send to the chip
write74673()
{
    for i in $(seq 0 0xf); do
	PINVALUE="$(( $4 >> $i & 1 ))"
	gpiowrite "$2" 1
	gpiowrite "$3" "$PINVALUE"
	gpiowrite "$2" 0
#	echo "$i $PINVALUE"
    done
    gpiowrite "$3" 0
    gpiowrite "$1" 1
    gpiowrite "$1" 0
}

gpioexport $CLOCKPIN
gpiosetdir $CLOCKPIN out
gpioexport $STROBEPIN
gpiosetdir $STROBEPIN out
gpioexport $DATAPIN
gpiosetdir $DATAPIN out

while true; do
    for i in $(seq 0 0xf); do
#	echo "$(( 1 << $i ))"
        write74673 $STROBEPIN $CLOCKPIN $DATAPIN "$(( 1 << $i ))"
	# Write random junk to clock and data pins. Should not influence the shift register output until you hit the strobe line
#	for j in $(seq $(( $RANDOM % 20)) ) ; do
#	    gpiowrite $DATAPIN $(( $RANDOM & 1 ))
#	    gpiowrite $CLOCKPIN $(( $RANDOM & 1 ))
#	done
    done
    for i in $(seq  0xf -1 0 ); do
#	echo "$(( 1 << $i ))"
	# Write random junk to clock and data pins. Should not influence the shift register output until you hit the strobe line
#	for j in $(seq $(( $RANDOM % 20)) ) ; do
#	    gpiowrite $DATAPIN $(( $RANDOM & 1 ))
#	    gpiowrite $CLOCKPIN $(( $RANDOM & 1 ))
#	done        
	write74673 $STROBEPIN $CLOCKPIN $DATAPIN "$(( 1 << $i ))"
    done
done


11111