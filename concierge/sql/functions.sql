--
--	Concierge for Hackerspace Brussels - stored procedures definitions
--
--	(c) 2013 Frederic Pasteleurs <frederic@askarel.be>
--
--    This program is free software: you can redistribute it and/or modify
--    it under the terms of the GNU General Public License as published by
--    the Free Software Foundation, either version 3 of the License, or
--    (at your option) any later version.
--
--    This program is distributed in the hope that it will be useful,
--    but WITHOUT ANY WARRANTY; without even the implied warranty of
--    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
--    GNU General Public License for more details.
--
--    You should have received a copy of the GNU General Public License
--    along with this program.  If not, see <http://www.gnu.org/licenses/>.
--
DELIMITER ;;


CREATE FUNCTION `mkbecomm`() RETURNS char(20) CHARSET latin1
begin
set @commbase:=lpad (floor (1 + (rand() * 9999999999 )),10, '0');
return (select concat ('+++', insert (insert (@commbase, 8, 0, '/'), 4, 0, '/'), lpad ((case mod (@commbase, 97) when 0 then 97 else (mod (@commbase, 97))end),2,'0'), '+++'));
end ;;



-- Format any number between 0 and 9999999999 into a belgian style structured communication
CREATE FUNCTION formatbecomm (commnumber BIGINT) RETURNS char(20)
begin
 DECLARE commbase char(10);
 DECLARE commmod char (2);
 SET commbase:=lpad (commnumber, 10, '0');
 SET commmod:=lpad (( case mod (commbase, 97) when 0 then 97 else (mod (commbase, 97)) end), 2, '0');
 RETURN (select concat ('+++', insert (insert( commbase, 8, 0, '/'), 4, 0, '/'), commmod , '+++'));
end ;;



DELIMITER ;
