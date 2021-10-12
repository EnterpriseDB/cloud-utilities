# Cloud utilities

This repository contains utilities and scripts to help on using [EDB Cloud][1]

## Requirement

The below software utilities are required to be installed on the machine
where the scripts provided in this repository are used:

- [jq][3]
- [azure cli][4] v2.26 or above

## Scripts

### Calculate Azure Resource Quotas

[resource-quotas.sh](./azure/resource-quotas.sh) is a script used to calculate
if the Azure resource quota in your Azure subscription can meet the requirement
of the EDB Cloud.

It calls to Azure CLI and queries some specific resource types and check if there is
still available resources can be allocated for the dedicated use by EDB Cloud.

### Get Token for EDB Cloud API

[get-token.sh](./api/get-token.sh) is a script to obtain a token for accessing
the [EDB Cloud API][2].

For more details about EDB Cloud API, please refer to [Using the EDB Cloud API][5]

### Create a Azure AD SPN for EDB Cloud Signup

[create-spn.sh](./azure/create-spn.sh) is a script used to create a SPN with enough
permissions. The output can be used in EDB Cloud Signup page.


[1]: https://www.enterprisedb.com/docs/edbcloud/latest/
[2]: https://portal.edbcloud.com/api/docs/
[3]: https://stedolan.github.io/jq/
[4]: https://docs.microsoft.com/en-us/cli/azure/
[5]: https://www.enterprisedb.com/docs/edbcloud/latest/reference
