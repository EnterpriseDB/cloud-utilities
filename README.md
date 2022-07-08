# Cloud Utilities

This repository contains utilities and scripts to help on using [BigAnimal][1]

## Requirements

The below software utilities are required to be installed on the machine
where the scripts provided in this repository are used:

- [jq][3]
- [azure cli][4] v2.26 or above (if runs against Azure)
- [aws-cli][6] v.2.3.0 or above (if runs against AWS)
- [BASH][8] AWS preflight scripts require BASH 4 or newer the default in macOS is 3.x

All 4 of these can be installed using the guides noted at the end of this dock or using homebrew.

## Azure Scripts

### Check Azure subscription readiness for running BigAnimal

[biganimal-csp-preflight](./azure/biganimal-csp-preflight) is a script used to check the
Azure subscription readiness for running the BigAnimal by:

- if your any of your Azure provider has not been registered
- if the virtual-machine SKU in the given region has any restriction
- if the Azure resource quota in your Azure subscription can meet the requirement of
  the BigAnimal

It calls to Azure CLI and queries some specific resource types and check if there is
still available resources can be allocated for the dedicated use by BigAnimal.

### Create a Azure AD SPN for BigAnimal Signup

[biganimal-csp-setup](./azure/biganimal-csp-setup) is a script used to create
a SPN with enough permissions. The output can be used in BigAnimal Signup page.

## AWS Scripts

### Check AWS account readiness for running BigAnimal

[biganimal-csp-preflight](./aws/biganimal-csp-preflight) is a script used to check the
AWS account readiness for running the BigAnimal by checking:

- if the AWS CLI is correctly configured
- if the AWS service quota in your AWS account can meet the requirement of BigAnimal

It uses the AWS CLI and queries for some specific resource types checking if there are
available resources that can be allocated for the usage requirement of BigAnimal.

### Create an AWS IAM policy and role for BigAnimal Cloud Account Connect

[biganimal-csp-setup](./aws/biganimal-csp-setup) is a script used to create an
IAM policy and an IAM role with enough permissions. The script will create a "ba-passport.json"
file that can be used by the [BigAnimal CLI][7] to connect your AWS account with your BigAnimal
account.
You can find an easy readable version (pretty print) of both the IAM policy and the
IAM Trust Policy applied to the created IAM role here:
[biganimal_AWS_basepolicy.json](./aws/biganimal_AWS_basepolicy.json)
[biganimal_AWS_trustpolicy](./aws/biganimal_AWS_trustpolicy.json)

## BigAnimal API Scripts

[get-token.sh](./api/get-token.sh) is a script to obtain a token for accessing the [BigAnimal API][2].

For more details about BigAnimal API, please refer to [Using the BigAnimal API][5]

[1]: https://www.enterprisedb.com/docs/biganimal/latest/
[2]: https://portal.biganimal.com/api/docs/
[3]: https://stedolan.github.io/jq/
[4]: https://docs.microsoft.com/en-us/cli/azure/
[5]: https://www.enterprisedb.com/docs/biganimal/latest/reference/api/
[6]: https://aws.amazon.com/cli/
[7]: https://www.enterprisedb.com/docs/biganimal/latest/reference/cli/
[8]: https://formulae.brew.sh/formula/bash
