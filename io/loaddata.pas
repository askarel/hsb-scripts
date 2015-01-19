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

uses unixtype, sysutils, daemon;

CONST pchararraytest:ARRAY[1..6] of pchar=('this','is','a', 'pchar string', 'test',':-)');

TYPE TPPchar=array of pchar;
     TPPPChar=^TPPchar;
     TCharBuffer= array of char;
     TPByte=^char;
//     TPByte=^TCharbuffer;
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
        lastioop: word;
        textdata: pointer;
        dataread: longint;
begin
 {$I-}
 loadfile.data:=nil; // Assume failure
 assign (f, filename);
 reset (f,1);
 lastioop:=ioresult;
 if lastioop = 0 then
  begin
   getmem (textdata, filesize (f));
   if textdata <> nil then
   begin
    blockread (f, textdata^, filesize (f), dataread); // Got buffer: Suck it in
    lastioop:=ioresult;
    if lastioop = 0 then
     begin // Success
      loadfile.data:=textdata;
      loadfile.size:=dataread;
     end
     else
     begin // Failure: free the block and return error code
      freemem (textdata);
      loadfile.size:=lastioop;
     end;
   end;
   close (f);
  end
  else // Cannot allocate buffer
   loadfile.size:=lastioop;
 {$I+}
end;

function buffer_to_pchar_array (var textbufferdata: TFlatfile):pointer;
var i: longint;
begin
 for i:=0 to textbufferdata.size do if (textbufferdata.data[i] = #10) or (textbufferdata.data[i] = #13) then textbufferdata.data[i]:=#0;
// buffer_to_pchar_array:=pointer (textbufferdata.data);
 buffer_to_pchar_array:=textbufferdata.data;
end;

// Scan and parse the buffer. Fill output structure if there is a match
function gettagdata (textbufferdata: TFlatfile; searchtag: string): TFlatAccessData;
TYPE SMStates=(LINEBEGIN, WASTELINE, STARTDATE, ENDDATE, FLAGS, STATUS, NICK);
var workstr: string;
    state: SMStates;
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
    testarray: ^PChar;
    passeddata: TFlatAccessData;
    passwddata: Ppasswd;
    i, line: longint;
begin
 line:=0;
 passwddata:=getpwnam ('avahi-autoipd');
 writeln (' User name=', passwddata^.pw_name);
 writeln (' User password=', passwddata^.pw_passwd);
 writeln (' UID=', passwddata^.pw_uid);
 writeln (' GID=', passwddata^.pw_gid);
 writeln (' homedir=', passwddata^.pw_dir);
 writeln (' shell=', passwddata^.pw_shell);
 writeln (' Gecos=', passwddata^.pw_gecos);

 testptr:=loadfile ('rfidpoll.txt');
 if testptr.data=nil then
  begin
   writeln ('Failed to load data');
   halt (1);
  end;
 for i:=0 to testptr.size do if (testptr.data[i] = #10) or (testptr.data[i] = #13) then
  begin
   line:=line+1;
   writeln ('Line ',line,': newline at offset ', i);//testptr.data[i]:=#0;
  end;
 testarray:=pointer (testptr.data);
// writeln ('high (testptr.data)= ', ord (high (testptr.data^)));
// writeln (inttohex (qword (testarray), 16 ));
 writeln (testarray^[0]);
{
 passeddata:=gettagdata (testptr, '68847c5bdc3538295e42c354e636f1da');
 writeln ('Returned TFlatAccessData content:');
 writeln (' taghash=', passeddata.taghash);
 writeln (' starttime=', passeddata.starttime);
 writeln (' endtime=', passeddata.endtime);
 writeln (' flags=', passeddata.flags);
 writeln (' revoked=', passeddata.revoked);
 writeln (' username=', passeddata.username);
}
end.
