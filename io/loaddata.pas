program loaddatafile;
{
  Implementation of a finite state machine to parse a memory buffer filled with a text file

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

uses unixtype, sysutils;

TYPE TPByte=^char;
     TFlatAccessData=RECORD
        taghash: string;
        starttime, endtime: time_t;
        flags, revoked: longint;
        username: string;
        end;

     TFlatFile=RECORD
        data: TPByte;
        size: longint;
        end;


// Load a file into memory and return a pointer to it. NIL in case of failure
function loadfile (filename: string): TFlatfile;
var     f: file;
        textdata: pointer;
        dataread: longint;
begin
 loadfile.data:=nil; // Assume failure
 assign (f, filename);
 reset (f,1);
 if ioresult = 0 then
  begin
   getmem (textdata, filesize (f));
   if textdata <> nil then
   begin
    blockread (f, textdata^, filesize (f), dataread); // Got buffer: Suck it in
    loadfile.data:=textdata;
    loadfile.size:=dataread;
   end;
   close (f);
  end
  else
   loadfile.size:=ioresult;
end;

// Scan and parse the buffer. Fill output structure if there is a match
function gettagdata (textbufferdata: TFlatfile; searchtag: string): TFlatAccessData;
CONST LINEBEGIN=0; WASTELINE=1; STARTDATE=2; ENDDATE=3; FLAGS=4; STATUS=5; NICK=6;
var workstr: string;
    state: byte;
    i, lineno: longint;
begin
 fillchar (gettagdata, sizeof (TFlatAccessData), 0); // Assume failure: prepare a null answer
 workstr:='';
 state:=LINEBEGIN;
 for i:=0 to textbufferdata.size do // Scan buffer
  case state of // First attempt at building a finite state machine
   LINEBEGIN: // State: beginning of line
    case textbufferdata.data[i] of
     ' ', #9, ',', ';': // Got field separator: first field is complete
      if workstr = searchtag then
       begin
        gettagdata.taghash:=workstr;
        state:=STARTDATE; // Got tag! Now fetch data
        workstr:='';
       end
       else state:=WASTELINE; // Wrong tag: skip line
     #10:       // ??? Got end of line ???
       workstr:='';
     else workstr:=workstr+textbufferdata.data[i]; // Extract tag
    end;
   WASTELINE: // State: advance to next line
    if textbufferdata.data[i] = #10 then
     begin
      state:=LINEBEGIN;
      workstr:='';
     end;
   STARTDATE: // State: get start date
    case textbufferdata.data[i] of
     ' ', #9, ',', ';': // Got field separator: second field is complete
      begin
       gettagdata.starttime:=strtoint (workstr);
       state:=ENDDATE;
       workstr:='';
      end;
     #10:       // ??? Got end of line ???
       begin
        state:=LINEBEGIN;
        workstr:='';
       end;
     else workstr:=workstr+textbufferdata.data[i]; // Extract startdate
    end;
   ENDDATE: // State: get end date
    case textbufferdata.data[i] of
     ' ', #9, ',', ';': // Got field separator: third field is complete
      begin
       if workstr = 'NULL' then workstr:='0';
       gettagdata.endtime:=strtoint (workstr);
       state:=FLAGS;
       workstr:='';
      end;
     #10:       // ??? Got end of line ???
       begin
        workstr:='';
        state:=LINEBEGIN;
       end;
     else workstr:=workstr+textbufferdata.data[i]; // Extract enddate
    end;
   FLAGS: // State: get card flags
    case textbufferdata.data[i] of
     ' ', #9, ',', ';': // Got field separator: fourth field is complete
      begin
       gettagdata.flags:=strtoint (workstr);
       state:=STATUS;
       workstr:='';
      end;
     #10:       // ??? Got end of line ???
       begin
        state:=LINEBEGIN;
        workstr:='';
       end;
     else workstr:=workstr+textbufferdata.data[i]; // Extract flags
    end;
   STATUS: // State: get revocation status
    case textbufferdata.data[i] of
     ' ', #9, ',', ';': // Got field separator: fifth field is complete
      begin
       gettagdata.revoked:=strtoint (workstr);
       state:=NICK;
       workstr:='';
      end;
     #10:       // ??? Got end of line ???
       begin
        state:=LINEBEGIN;
        workstr:='';
       end;
     else workstr:=workstr+textbufferdata.data[i]; // Extract revocation status
    end;
   NICK: // State: get username
    if textbufferdata.data[i] = #10 then       // Got end of line
     begin
      gettagdata.username:=workstr;
      state:=LINEBEGIN;
      workstr:='';
      break;
     end
    else workstr:=workstr+textbufferdata.data[i]; // Extract username
  end;
end;

var testptr: TFlatfile;
    passeddata: TFlatAccessData;
begin
 testptr:=loadfile ('rfidpoll.txt');
 passeddata:=gettagdata (testptr, '68847c5bdc3538295e42c354e636f1da');
 writeln ('Returned TFlatAccessData content:');
 writeln (' taghash=', passeddata.taghash);
 writeln (' starttime=', passeddata.starttime);
 writeln (' endtime=', passeddata.endtime);
 writeln (' flags=', passeddata.flags);
 writeln (' revoked=', passeddata.revoked);
 writeln (' username=', passeddata.username);
end.
