--
--	Concierge for Hackerspace Brussels - triggers definition
--
--	(c) 2014 Frederic Pasteleurs <frederic@askarel.be>
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

DROP TRIGGER if exists log_person_activity_update;;
CREATE TRIGGER log_person_activity_update AFTER UPDATE ON person FOR EACH ROW
    begin
	if new.machinestate <> old.machinestate or new.machinestate_data <> old.machinestate_data then
	    INSERT INTO person_history (event_timestamp, member_id, machinestate, machinestate_data) VALUES (NOW(), old.id, new.machinestate, new.machinestate_data);
	end if;
    end;;

DROP TRIGGER if exists log_person_activity_insert;;
CREATE TRIGGER log_person_activity_insert AFTER INSERT ON person FOR EACH ROW
	INSERT INTO person_history (event_timestamp, member_id, machinestate, machinestate_data) VALUES (NOW(), new.id, new.machinestate, new.machinestate_data);;

DROP TRIGGER if exists person_auto_entry_date;;
create trigger person_auto_entry_date before insert on person for each row 
    begin
	set new.entrydate=current_date;
	if new.nickname = '' or new.nickname = NULL then
	    set new.nickname= concat (new.firstname, '_',new.name); -- Craft an unlikely nickname :-)
	end if;
    end;;

DELIMITER ;
