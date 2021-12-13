# Cloud utilities

This repository contains utilities and scripts to help on using [BigAnimal][1]

## Requirement

The below software utilities are required to be installed on the machine
where the scripts provided in this repository are used:

- [jq][3]
- [azure cli][4] v2.26 or above

## Scripts

### Check Azure subscription readiness for running BigAnimal

[biganimal-preflight-azure](./azure/biganimal-preflight-azure) is a script used to check the
Azure subscription readiness for running the BigAnimal by:

- if your any of your Azure provider has not been registered
- if the virtual-machine SKU in the given region has any restriction
- if the Azure resource quota in your Azure subscription can meet the requirement of
  the BigAnimal

It calls to Azure CLI and queries some specific resource types and check if there is
still available resources can be allocated for the dedicated use by BigAnimal.

### Get Token for BigAnimal API

[get-token.sh](./api/get-token.sh) is a script to obtain a token for accessing
the [BigAnimal API][2].

For more details about BigAnimal API, please refer to [Using the BigAnimal API][5]

### Create a Azure AD SPN for BigAnimal Signup

[create-spn.sh](./azure/create-spn.sh) is a script used to create a SPN with enough
permissions. The output can be used in BigAnimal Signup page.

[1]: https://www.enterprisedb.com/docs/biganimal/latest/
[2]: https://portal.biganimal.com/api/docs/
[3]: https://stedolan.github.io/jq/
[4]: https://docs.microsoft.com/en-us/cli/azure/
[5]: https://www.enterprisedb.com/docs/biganimal/latest/reference
