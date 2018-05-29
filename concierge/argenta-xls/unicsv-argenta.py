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
parser.add_argument('excel_file')

args = parser.parse_args()
book = xlrd.open_workbook(args.excel_file)
datemode = book.datemode

transactions = xls_to_dict(book)

for transaction in transactions:
    transaction.pop('Description')
    transaction.pop('Date de la transaction')
    transaction['@date_val'] = csv_date_format(transaction.pop('Date valeur'), datemode)
    transaction['@date_account'] = csv_date_format(transaction.pop('Date comptable'), datemode)
    transaction['this_account'] = "".join(transaction.pop('Compte').split())
    transaction['other_account'] = "".join(transaction.pop('Compte de la contrepartie').split())
    transaction['amount'] = transaction.pop('Montant')
    transaction['currency'] = transaction.pop('Devise')
    transaction['message'] = transaction.pop('Communication')
    transaction['other_account_name'] = transaction.pop('Nom de la contrepartie')
    transaction['transaction_id'] = "BANK/ARGENTA/" + transaction['this_account'] + \
                                    "/" + transaction.pop('Référence')

w = csv.DictWriter(sys.stdout, transactions[0].keys(), delimiter=";", quoting=csv.QUOTE_ALL)
w.writeheader()
w.writerows(transactions)
