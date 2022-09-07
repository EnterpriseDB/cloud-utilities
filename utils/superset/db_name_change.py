"""
This script will generate the upload JSON for the entered database name.
"""
import json
import argparse
import logging
import sys
from pathlib import PurePath


# create logger
logging.basicConfig(level=logging.DEBUG)


def file_handle_error(function):
    """
    Decorator to handle the exceptions while reading or writing to the file.
    """
    def exception_handle(*arguments):
        try:
            return function(*arguments)
        except FileNotFoundError:
            msg = f"File '{arguments[0]}' not found. Aborting"
            logging.error(msg)
            sys.exit(1)
        except IOError as exception:
            msg = f"I/O error '{exception.errno}': '{exception.strerror}'"
            logging.error(msg)
            sys.exit(1)
        except Exception as err:
            msg = f"Unexpected error while writing to the file: '{err}'"
            logging.error(msg)
            sys.exit(1)
    return exception_handle


@file_handle_error
def read_input_file(input_file, db_name):
    """
    Input file function to read the file content and replace the database name.
    """
    file_data = {"dashboards": [], "datasources": []}
    if PurePath(input_file).suffix == ".json":
        with open(input_file, encoding="utf_8") as file_obj:
            db_template = json.load(file_obj)
            dashboards = db_template["dashboards"]
            for dashboard in dashboards:
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
    else:
        raise argparse.ArgumentTypeError('File must have JSON extension')

    return file_data


@file_handle_error
def write_output_file(output_file, file_data):
    """
    This function will write the file.
    """
    if PurePath(output_file).suffix == ".json":
        with open(output_file, 'w', encoding="utf_8") as file_obj:
            json.dump(file_data, file_obj, indent=4)
    else:
        raise argparse.ArgumentTypeError('File must have JSON extension')


if __name__ == "__main__":

    parser = argparse.ArgumentParser()
    parser.add_argument("database_name")
    parser.add_argument("-i", "--input_file", type=str, default="pgd_monitoring_template.json")
    parser.add_argument("-o", "--output_file", type=str, default="upload.json")
    args = parser.parse_args()
    msg = f"Database name entered: {args.database_name}"
    logging.info(msg)

    file_data_template = read_input_file(args.input_file, args.database_name)
    write_output_file(args.output_file, file_data_template)

    msg = (f"Upload file generated. Please import the '{args.output_file}' "
           f"file in your Superset using Import Dashboard option under "
           f"Settings menu on Database '{args.database_name}'")
    logging.info(msg)
