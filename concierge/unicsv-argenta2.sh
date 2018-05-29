#!/bin/bash

ME=$(basename $0)

# 	Argenta CSV parser, formatter and sanitizer, Excel version
#	(c) 2018 Frederic Pasteleurs <frederic@askarel.be>
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

# This is just a wrapper script.

# Function to call when we bail out
die()
{
    printf "%s: %s. Exit\n" "$ME" "$1"
    test -z "$2" && exit 1 || exit $2
}



case "$1" in
    'header')
	python3 ./argenta-xls/unicsv-argenta.py header
    ;;
    'import')
        test -z "$2" && die "No file specified"
        test -f "$2" || die "File '$2' does not exist or not regular file"
	python3 ./argenta-xls/unicsv-argenta.py import "$2"
    ;;
    'install')
	echo 'todo'
    ;;
    *)
        echo "usage: $ME [import|header] filename"
        exit 1
    ;;
esac
exit 0
