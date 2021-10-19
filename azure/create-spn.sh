#!/bin/bash
#
# This script is used to create a SPN(Service Principal Name) with enough
# permissions in your Azure subscription for handling the EDB Cloud managed
# service.
#
# What it does:
#   - assume you have already login to your Azure AD(Active Directory) directory by Azure CLI
#   - set your Azure CLI context to the given subscription
#   - create a new client app in the Azure AD directory
#   - assign this client app the role of "ower" of the given subscription
#
# it finally outputs the:
#   - client app Id
#   - client app secret
#   - your Azure subscription Id
# These outputs will be used in the EDB Cloud Signup submission form.
#
# For more details, please refer to
#  https://www.enterprisedb.com/docs/edbcloud/latest/getting_started/02_connect_cloud_account
#
set -e

display_name=""
subscription=""
years=""

spn=""

show_help()
{
  echo "Required permissions:"
  echo "  Microsoft.Authorization/roleAssignments/write"
  echo "Required tools:"
  echo "  jq"
  echo "Usage:"
  echo "  $0 -d NAME -s SUBSCRIPTION_ID [options]"
  echo ""
  echo "Options:"
  echo "  -d, --display-name: The name of Azure AD App."
  echo "  -s, --subscription: The Azure Subscription ID used by EDB Cloud."
  echo "  -y, --years:        [Optional] The Number of years for which the credentials will be valid. Only accept positive integer value. Default: 1 year."
  echo "  -h, --help:         Show this help."
  echo ""
}

check()
{
  # jq is required.
  hash jq > /dev/null 2>&1 || { show_help; echo "Error: please install jq on the system"; }
  check_display_name
  check_subscription
}

check_display_name()
{
  if [[ "${display_name}" == "" ]]; then
    show_help
    echo "Error: missing -d, --display-name to specify Azure AD App name"
    exit 1
  fi
}

check_subscription()
{
  if [[ "${subscription}" == "" ]]; then
    show_help
    echo "Error: missing -s, --subscription to specify Azure Subscription"
    exit 1
  fi
}

check_years()
{
  if [[ "${years}" == "" ]]; then
    show_help
    echo "Error: -y, --years should have a value"
    exit 1
  fi
}

while [[ $# -gt 0 ]]; do
  key="$1"

  case $key in
    -h|--help)
      show_help
      exit 0
      ;;
    -d|--display-name)
      display_name="$2"
      check_display_name
      shift 2
      ;;
    -s|--subscription)
      subscription="$2"
      check_subscription
      shift 2
      ;;
    -y|--years)
      years="$2"
      check_years
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

set_subscription()
{
  echo "Change to use Azure Subscription ${subscription}..."
  az account set --subscription ${subscription}
}

show_account()
{
  az account show
}

create_ad_sp()
{
  echo "Creating Azure AD Service Principal and configuring its access to Azure resources in subscription ${subscription}..."
  years="${years:-1}"
  spn=$(az ad sp create-for-rbac -o json -n ${display_name} --role Owner --scopes /subscriptions/${subscription} --years ${years})
}

print_result()
{
  local client_id=$(echo ${spn} | jq -r .appId)
  local client_secret=$(echo ${spn} | jq -r .password)
  jq --null-input \
    --arg client_id ${client_id} \
    --arg client_secret ${client_secret} \
    --arg subscription ${subscription} \
    '{"client_id":$client_id,"client_secret":$client_secret,"subscription":$subscription}'
}

check
set_subscription
show_account
create_ad_sp
print_result
