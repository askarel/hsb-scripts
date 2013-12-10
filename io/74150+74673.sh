#! /bin/sh
#
#	Controlling shift register and input multiplexer from the shell
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

# 74ls673
# Pin 2: SHCLK
CLOCKPIN="7"
# Pin 5: STRCLK
STROBEPIN="8"
# Pin 6: SER pin
DATAPIN="25"

# 74150
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

gpioexport $CLOCKPIN
gpioexport $STROBEPIN
gpioexport $DATAPIN
gpioexport $READOUT
gpiosetdir $CLOCKPIN out
gpiosetdir $STROBEPIN out
gpiosetdir $DATAPIN out
gpiosetdir $READOUT in

# parameter 1: strobe pin
# parameter 2: clock pin
# parameter 3: data pin
# parameter 4: word to send to the chip
write74673()
{
    local i
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

# Do an I/O cycle on the board. Read operation automatically update the output
# Parameter 1: Shift register Strobe pin
# Parameter 2: Shift register clock pin
# Parameter 3: Shift register data pin
# Parameter 4: Input from multiplexer
# Parameter 5: Value to apply to the shift register
io_673_150()
{
    local i
    GPIOWORD=0
    for i in $(seq 0 0xf); do
	write74673 $1 $2 $3 $(( ($5 & 0x0fff) | ( ( ( $i >> 1 ) ^ $i ) << 0xc) ))
        GPIOWORD=$((  $GPIOWORD | ( $(gpioread $4 ) << ( ( $i >> 1 ) ^ $i )  ) ))
#	write74673 $1 $2 $3 $(( ($5 & 0x0fff) | ( $i << 0xc) ))
#        GPIOWORD=$((  $GPIOWORD | ( $(gpioread $4 ) << $i )  ))
#	echo "debug: $i $GPIOWORD $(gpioread $4)"
#	sleep 1
    done
    echo "$GPIOWORD"
}

# Decompose a number into it's binary equivalent
# parameter 1: number to bitify
# parameter 2: amount of bits to display
# output: bunch of bits
bitify()
{
    local i
    local BITS
    for i in $(seq $(( $2 - 1 )) -1 0); do
	BITS="$BITS$(( ( $1 >> $i ) & 1 ))"
    done
    echo $BITS
}

while true; do
    for i in $(seq 0 0xb); do
	echo  "$(date) Write: $( bitify $(( 1 << $i )) 16 ), Read: $(bitify $(io_673_150 $STROBEPIN $CLOCKPIN $DATAPIN $READOUT $(( 1 << $i )) ) 16 )"
    done
    for i in $(seq  0xb -1 0 ); do
	echo  "$(date) Write: $( bitify $(( 1 << $i )) 16 ), Read: $(bitify $(io_673_150 $STROBEPIN $CLOCKPIN $DATAPIN $READOUT $(( 1 << $i )) ) 16 )"
    done
done

