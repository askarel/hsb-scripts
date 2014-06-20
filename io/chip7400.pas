UNIT chip7400;
{
 chip7400 - TTL library for shift registers and other functions

 (c) 2014 Frederic Pasteleurs <frederic@askarel.be>

 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation; either version 3 of the License, or
 (at your option) any later version.

 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with this program or from the site that you downloaded it
 from; if not, see <http://www.gnu.org/licenses/>.

}

INTERFACE
TYPE    TRegisterbits=bitpacked array [0..15] of boolean; // Like a word: a 16 bits bitfield
        TRegister8bits=bitpacked array [0..7] of boolean; // Like a byte: a 8 bits bitfield (for smaller chips)
        TSetBit=procedure (bitstate:boolean); // Callback to set a bit
        TGetBit=function: boolean; // Callback to read a bit

CONST   SETB=true; RESETB=false;
        bits:array [false..true] of char=('0', '1');


function graycode (inp: longint): longint;
function word2bits (inputword: word): TRegisterbits;
function bits2word (inputbits: TRegisterbits): word;
function bits2str (inputbits: TRegisterbits): string;


IMPLEMENTATION

// Return gray-encoded input
function graycode (inp: longint): longint;
begin
 graycode:=(inp shr 1) xor inp;
end;

function word2bits (inputword: word): TRegisterbits;
begin
 word2bits:=TRegisterbits (inputword); // TRegisterbits is a word-sized array of bits
end;

function bits2word (inputbits: TRegisterbits): word;
begin
 bits2word:=word (inputbits);
end;

function bits2str (inputbits: TRegisterbits): string;
var i: byte;
    s: string;
begin
 s:='';
 for i:=(bitsizeof (TRegisterbits)-1) downto 0 do s:=s+bits[inputbits[i]];
 bits2str:=s;
end;

END.

