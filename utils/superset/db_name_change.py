from io import IOBase
import os
import json
import argparse
import logging
from pyexpat import ErrorString
import sys


DATABASE_NAME = "template_database_name"

# create logger
logging.basicConfig(level=logging.DEBUG)


# file extension validation
def validate_extension(file_name):
    _, ext = os.path.splitext(file_name)
    if ext.lower() != ('.json') or len(ext) == 0:
        raise argparse.ArgumentTypeError('File must have JSON extension')
    return True

if __name__ == "__main__":

    parser = argparse.ArgumentParser()
    parser.add_argument("-d", "--database_name", required=True, type=str)
    parser.add_argument("-i", "--input_file", type=str, default="import_template.json")
    parser.add_argument("-o", "--output_file", type=str, default="upload.json")
    args = parser.parse_args()

    logging.info(f"Database name entered: {args.database_name}")

    try:
        if all([validate_extension(args.input_file), validate_extension(args.output_file)]):
            with open(args.input_file) as f:
                file_data = f.read()
            file_data = file_data.replace(f"{DATABASE_NAME}", args.database_name)

            with open(args.output_file, 'w') as f:
                f.write(file_data)

    except FileNotFoundError:
        logging.error(f"File '{args.input_file}' not found. Aborting")
        sys.exit(1)
    except IOError as e:
        logging.error(f"I/O error {e.errno}: {e.strerror}")
        sys.exit(1)
    except Exception as err:
        logging.error(f"Unexpected error while writing to the file: {err}")
        sys.exit(1)

    logging.info(f"Upload file generated. Please import the '{args.output_file}' file in your Superset")
