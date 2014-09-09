--
--	Concierge for Hackerspace Brussels - tables definition
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

create table if not exists hsbmembers (id int not null auto_increment primary key, 
				    entrydate date not null, 
				    structuredcomm char(21) unique not null, 
				    firstname char(40) not null, 
				    name char(40) not null, 
				    nickname char(30), 
				    phonenumber char(20), 
				    emailaddress char(255) not null, 
				    remind_membership_on date,
--				    exitdate date, 
				    passwordhash char(60) not null default 'mouh', 
--				    flags bigint not null default 0,
				    birthdate date, 
				    openpgpkeyid char(20), 
--				    activateddate date, 
--				    mail_flags bigint not null default 0, 
				    why_member text not null,
--				    json_data text,
				    sshpubkeys text
				    );

create table if not exists member_sponsors (id int not null auto_increment primary key,
				    member_id int not null,
				    sponsor_id int
				    );

create table if not exists member_history (id int not null auto_increment primary key,
				    member_id int not null,
				    event_date date not null,
				    event_code int not null,
				    event_string text
				    );

create table if not exists member_groups (id int not null auto_increment primary key,
				    member_id int not null,
				    group_id int not null
				    );

create table if not exists hsb_groups (id int not null auto_increment primary key,
				    shortdesc char(50) unique not null,
				    fulldesc text
				    );

create table if not exists bankstatements (id int not null auto_increment primary key,
				    date_val date,
				    date_account date,
				    this_account char(40),
				    other_account char (40),
				    amount decimal (15,2) not null,
				    currency char (5) not null, -- should be enum
				    message char (60),
				    other_account_name char (50),
				    transactionhash binary(20) unique not null,
				    fix_fuckup_msg char (60)
				    );

create table if not exists validiban (id int not null auto_increment primary key,
				    country char(2) unique not null,
				    validlength int not null);

create table if not exists expenses (id int not null auto_increment primary key,
				    submitter_id int not null,
				    description text not null,
				    dest_account char (40),
				    amount decimal (15,2) not null,
				    currency char (5) not null, -- should be enum
				    message char (60),
				    occurence int not null, -- should be enum
				    pay_method int not null, -- should be enum
				    deadline_date date,
				    submit_date date,
				    start_date date,
				    stop_date date,
				    flags int, -- should be a bitfield
				    category int not null, -- should be enum
				    in_year_seq_no int not null);

