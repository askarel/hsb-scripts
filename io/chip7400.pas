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
        TSetAddress=procedure (address: word); // Callback to set address lines

CONST   SETB=true; RESETB=false;
        bits:array [false..true] of char=('0', '1');


function graycode (inp: longint): longint;
function word2bits (inputword: word): TRegisterbits;
function bits2word (inputbits: TRegisterbits): word;
function bits2str (inputbits: TRegisterbits): string;
procedure wastecpucycles (waste: word);
procedure ls673_write (pin2, pin6, pin5: TSetBit; data: TRegisterbits);
function ls150_read (address:TSetAddress): TRegisterbits;


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

// Apparently, despite the crappy CPU on the raspberry pi, it is too fast for the shift register.
// This should help the shift register to settle
procedure wastecpucycles (waste: word);
var i: word;
begin
 for i:=0 to waste do
  asm
   nop // How handy... This is portable ASM... :-)
  end;
end;

// Send out a word to the 74LS673
// This procedure know how to *talk* to the chips, but not how to access them
procedure ls673_write (pin2, pin6, pin5: TSetBit; data: TRegisterbits);
CONST WASTE=4;
var i: byte;
begin
 for i:=0 to 15 do
 begin
  pin2 (true);
  wastecpucycles (WASTE);
  pin6 (data[i]);
  wastecpucycles (WASTE);
  pin2 (false);
  wastecpucycles (WASTE);
 end;
 pin5 (true);
 wastecpucycles (WASTE);
 pin5 (false);
end;

// Read all inputs from 74LS150. Setting the address of the multiplexer
// is implementation specific, use a callback to set the address.
function ls150_read (address:TSetAddress): TRegisterbits;
begin

end;

END.

