# Script to rename the database name 

The purpose of the script is to update the dashboard JSON template file with the database name of the user’s environment. 

This script will generate the new upload JSON file with the database name of the user and will be ready to import to have the PGD dashboard.  

Requires user to pass the database_name (which should be present in his/her environment) and optional input file and output file in JSON format as an argument in the script execution. The default extension is JSON for both input and output files. 

# Requirements

    Python 3.x 

# Run Comamnd

    python3 db_name_change.py -d <database_name> -i <input_file> -o <output_file>

# Usage
    usage: db_name_change.py [-h] -d DATABASE_NAME [-i INPUT_FILE] [-o OUTPUT_FILE]

    optional arguments:
        -h, --help            show this help message and exit
        -d DATABASE_NAME,     --database_name DATABASE_NAME
        -i INPUT_FILE,        --input_file INPUT_FILE
        -o OUTPUT_FILE,       --output_file OUTPUT_FILE
