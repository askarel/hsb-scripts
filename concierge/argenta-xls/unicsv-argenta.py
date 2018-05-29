# 	Argenta Excel parser HSBXL 
#	(c) 2018 Vincent Baggerman <vincent@baggerman.email>
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

import argparse
import csv
import sys

import xlrd

def make_json_from_data(column_names, row_data):
    """
    take column names and row info and merge into a single json object.
    :param data:
    :param json:
    :return:
    """
    row_list = []
    for item in row_data:
        json_obj = {}
        for i in range(0, column_names.__len__()):
            json_obj[column_names[i]] = item[i]
        row_list.append(json_obj)
    return row_list

def xls_to_dict(book):
    """
    Convert the read xls file into JSON.
    :param workbook_url: Fully Qualified URL of the xls file to be read.
    :return: json representation of the workbook.
    """
    sheet = book.sheet_by_index(0)
    columns = sheet.row_values(0)
    rows = []
    for row_index in range(1, sheet.nrows):
        row = sheet.row_values(row_index)
        rows.append(row)
    sheet_data = make_json_from_data(columns, rows)
    return sheet_data

def csv_date_format(value, xldatemode):
    return xlrd.xldate_as_datetime(value, xldatemode).date().isoformat()

parser = argparse.ArgumentParser(description='Process the Argenta Excel file')
parser.add_argument('output', choices=["import", "header"], help="import|header")
parser.add_argument('excel_file', nargs="*")

headers = ['@date_val', '@date_account', 'this_account', 'other_account',
           'amount', 'currency', 'message', 'other_account_name', 'transaction_id']

args = parser.parse_args()

w = csv.writer(sys.stdout, headers, delimiter=";", quoting=csv.QUOTE_ALL)

if args.output == "header":
    w.writerow(headers)

elif args.output == "import":
    book = xlrd.open_workbook(args.excel_file[0])
    datemode = book.datemode

    transactions = xls_to_dict(book)

    for transaction in transactions:
        csv_line = [
            csv_date_format(transaction['Date valeur'], datemode),
            csv_date_format(transaction['Date comptable'], datemode),
            "".join(transaction['Compte'].split()),
            "".join(transaction['Compte de la contrepartie'].split()),
            transaction['Montant'],
            transaction['Devise'],
            transaction['Communication'],
            transaction['Nom de la contrepartie'],
            "BANK/ARGENTA/" + transaction['Compte'] + "/" + transaction['Référence']
        ]
        w.writerow(csv_line)
