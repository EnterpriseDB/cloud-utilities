"""
This script will generate the upload json for entered database name
"""
import os
import json
import argparse
import logging
import sys


# create logger
logging.basicConfig(level=logging.DEBUG)


# file extension validation
def validate_extension(file_name):
    """
    This will ensure that the input or output file will have a .json extension
    """
    _, ext = os.path.splitext(file_name)
    if ext.lower() != ('.json') or len(ext) == 0:
        raise argparse.ArgumentTypeError('File must have JSON extension')
    return True

def file_handle_error(function):
    """
    This decorator is to handle the exceptions while read, write to the file
    """
    def exception_handle(*arguments):
        try:
            return function(*arguments)
        except FileNotFoundError:
            logging.error("File '%s' not found. Aborting", arguments[0])
            sys.exit(1)
        except IOError as exception:
            logging.error("I/O error %s: %s",exception.errno, exception.strerror )
            sys.exit(1)
        except Exception as err: # pylint: disable=broad-except
            logging.error("Unexpected error while writing to the file: %s", err)
            sys.exit(1)
    return exception_handle

@file_handle_error
def read_input_file(input_file,db_name):
    """
    This is input file function to read the file content and replace the database name
    """
    file_data = {"dashboards":[], "datasources":[]}
    if validate_extension(input_file):
        with open(input_file, encoding="utf_8") as file_obj:
            db_template = json.load(file_obj)
            dashborads = db_template["dashboards"]
            for dashboard in dashborads:
                slices = dashboard["__Dashboard__"]["slices"]
                for dashboard_slice in slices:
                    db_params = json.loads(dashboard_slice["__Slice__"]["params"])
                    # Replacing the database name with passed argument
                    db_params["database_name"] = db_name
                    dashboard_slice["__Slice__"]["params"] = json.dumps(db_params)

                temp_dict = {"__Dashboard__": dashboard["__Dashboard__"]}
                file_data["dashboards"].append(temp_dict)

            datasources = db_template["datasources"]
            for datasource in datasources:
                db_params = json.loads(datasource["__SqlaTable__"]["params"])
                # Replacing the database name with passed argument
                db_params["database_name"] = db_name
                datasource["__SqlaTable__"]["params"] = json.dumps(db_params)

                temp_dict = {"__SqlaTable__": datasource["__SqlaTable__"]}
                file_data["datasources"].append(temp_dict)
    return file_data

@file_handle_error
def write_output_file(output_file, file_data):
    """
    This function will write the file
    """
    if validate_extension(output_file):
        with open(output_file, 'w', encoding="utf_8") as file_obj:
            json.dump(file_data,file_obj, indent=4)


if __name__ == "__main__":

    parser = argparse.ArgumentParser()
    parser.add_argument("database_name")
    parser.add_argument("-i", "--input_file", type=str, default="pgd_monitoring_template.json")
    parser.add_argument("-o", "--output_file", type=str, default="upload.json")
    args = parser.parse_args()

    logging.info("Database name entered: %s", args.database_name)

    file_data_template = read_input_file(args.input_file, args.database_name)
    write_output_file(args.output_file, file_data_template)
    logging.info(
        "Upload file generated. Please import the '%s' file in your Superset "
        "using Import Dashboard option under Settings menu", args.output_file
    )
