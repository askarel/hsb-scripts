--
--	Zoppas - tables definition
--
--	(c) 2017 Frederic Pasteleurs <frederic@askarel.be>
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

create table if not exists products (product_id int not null auto_increment primary key, 
				    description char(255),
				    shortdescription char(64),
				    category char(60),
				    stock_quantity int not null
				    );

create table if not exists barcodes (id int not null auto_increment primary key, 
				    product_id int not null,
				    barcode char(255) unique not null,
				    FOREIGN KEY(product_id) REFERENCES products(product_id)
				    );

create table if not exists price (id int not null auto_increment primary key, 
				    product_id int not null,
				    event_id char(40),
				    price_validfrom date not null,
				    price_validto date not null,
				    price_purchase decimal (15,4) not null,
				    price_sell decimal (15,4) not null,
				    FOREIGN KEY(product_id) REFERENCES products(product_id)
				    );

--create table if not exists sale_tickets ( -- id int not null auto_increment primary key, 
--				    product_id int not null,
--				    product_quantity int not null,
--				    product_unit_price decimal (15,4) not null,
--				    pointofsale char(60)
--				    );


