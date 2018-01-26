--
--	Concierge for Hackerspace Brussels - basic dataset to get started
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


INSERT INTO hsb_groups (shortdesc, fulldesc) VALUES 
			('root', 'Root group: members have all access to this system'),
			('members', 'Active members, paying their fair share'),
			('bank_access', 'Members of this group have access to the bank account. Spam them once a week to get the latest statements.'),
			('board', 'Members of the administrative board'),
			('sysadmins', 'Members of this group have administrator access to various systems in the space'),
			('landlord', 'The owner(s) of the house/building'),
			('Contractor', 'Any contractor that has to work in the space'),
			('Students', 'They usually benefit of a reduced membership fee'),
			('Cash_short', 'Nobody want to be part of this group.'),
			('Ex_Members', 'Members that decided to retire'),
			('webmasters', 'Website administrators'),
			('minors','Should be under adult supervision'),
			('cohabitants','People unrelated to the hackerspace, but living in the same building'),
			('guests','Guests, staying/using the space for a few days, do not want to be members for whatever reason');

