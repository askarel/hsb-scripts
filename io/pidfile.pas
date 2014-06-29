unit pidfile;
{
 pidfile.pas - routines to handle the PID file

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

interface

Procedure SavePid(pidfile: string; apid: integer);
function LoadPid(pidfile: string): integer;
Procedure DeletePid(pidfile: string);
function am_i_running (pidfile: string): boolean;
function getpidname: string;


implementation

uses baseunix, sysutils;

///////////// PID FILE HANDLING /////////////

Procedure SavePid(pidfile: string; apid: integer);
var fPid: text;
Begin
 Assign(fPid,pidfile);
 Rewrite(fPid);
 Writeln(fPid,apid);
 Close(fPid);
End;

function LoadPid(pidfile: string): integer;
var s: ansistring;
    fPid: text;
Begin
 Assign(fPid,pidfile);
 {$I-}
 Reset(fPid);
 Read(fPid,s);
 Close(fPid);
 {$I+}
 if (IOResult <> 0) and (pidfile <> '') then
  LoadPid := 0
 else
  LoadPid := strtoint(s);
End;

Procedure DeletePid(pidfile: string);
var fPid: text;
Begin
 {$I-}
 Assign(fPid,pidfile);
 erase (fPid);
 {$I+}
End;

// Determine if there is another copy running
function am_i_running (pidfile: string): boolean;
var mainpid : integer;
    cmdlinefile: text;
    procstr, s: string;
begin
 mainpid:=loadpid (pidfile);
 if mainpid = 0 then
  am_i_running:=false // Failed to load pidfile: we're not running.
 else
  begin
   str (mainpid, procstr);
   procstr:='/proc/' + procstr;
   if directoryexists (procstr) // There is a process ID linked to our PID file
    then
     procstr:=procstr + '/cmdline';
     Assign(cmdlinefile, procstr);
     {$I-}
     Reset(cmdlinefile);
     Read(cmdlinefile, s);
     Close(cmdlinefile);
     ioresult;
     {$I+}
     s:=copy (s, 1, pos (#0, s) -1 ); // Shave everything after and including the first NULL
     am_i_running:=extractfilename (s) = applicationName; // Is it ours ?
  end;
end;

function getpidname: string;
begin
// if fpGetUid = 0 then
  getpidname:='/run/lock/' + ApplicationName + '.PID'
// else
//  getpidname:=getEnvironmentVariable ('HOME') + '/.' + ApplicationName + '.PID';
end;



end.
