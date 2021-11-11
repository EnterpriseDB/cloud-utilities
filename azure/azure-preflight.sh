#!/bin/bash
#
# Copyright 2021 EnterpriseDB Corporation
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# This script is used as a preflight check to tell if the given location
# in your Azure subscription can meet the requirement for BigAnimal to create the
# PostgreSQL cluster in.
#
# Given one the below input:
#   - location
#   - PostgreSQL cluster's type (only support Azure ESv3 series)
#   - whether the HA (High Availability) is used for the PostgreSQL cluster
#   - network type (private, or public)
# it checks the below requirement:
#   - of the subscription for:
#     * the necessary Azure providers have been registered
#   - of the location in this subscription:
#     * if there is enough SKU(Stock Keeping Unit) left in that region for your PostgreSQL
#       cluster's type (of the Virtual Machine)
#     * if there is enough Virtual Machine quota left for this PostgreSQL cluster type
#       in your Azure subscription
#     * if there is enough IP left to expose the service for you to access the
#       PostgreSQL cluster
#
# The output of this script tells any unsatisfied condition and report in the form
# of table.
#
# For more details, please refer to:
#  https://www.enterprisedb.com/docs/biganimal/latest/getting_started/01_check_resource_limits/#increasing-network-quota
#
set -e

function show_help()
{
    echo "Usage:"
    echo "   $0 --location <location> --pgtype <pg-type> --endpoint <endpoint> [--ha] [--with-infra]"
    echo ""
    echo "     The available locations: ${AVAILABLE_LOCATIONS[@]}"
    echo "     The available PG types: ${AVAILABLE_PGTYPE[@]}"
    echo "     The available endpoints: ${AVAILABLE_ENDPOINTS[@]}"
    echo ""
}

AVAILABLE_ENDPOINTS=(
  public
  private
)

AVAILABLE_LOCATIONS=(
    brazilsouth
    canadacentral
    centralus
    eastus
    eastus2
    francecentral
    japaneast
    northeurope
    southcentralus
    uksouth
    westeurope
    westus2
)

AVAILABLE_PGTYPE=(
  e2s_v3
  e4s_v3
  e8s_v3
  e16s_v3
  e20s_v3
  e32s_v3
  e48s_v3
  e64s_v3
)

location=""

POSITIONAL=()
while [[ $# -gt 0 ]]; do
  key="$1"

  case $key in
    -l|--location)
      location="$2"
      shift # past argument
      shift # past value
      ;;
    -t|--pgtype)
      pg_type="$2"
      shift # past argument
      shift # past value
      ;;
    -e|--endpoint)
      endpoint="$2"
      shift # post argument
      shift # post value
      ;;
    --ha)
      ha=true
      shift # past argument
      ;;
    --with-infra)
      with_infra=true
      shift # past argument
      ;;
    *)    # unknown option
      POSITIONAL+=("$1") # save it in an array for later
      shift # past argument
      ;;
  esac
done

set -- "${POSITIONAL[@]}" # restore positional parameters

[ -z "$location" ] && show_help && echo "error: missed -l to specify Azure location" && exit 1
[ -z "$pg_type" ] && show_help && echo "error: missed -t to specify PG instance type" && exit 1
[ -z "$endpoint" ] && show_help && echo "error: missed -e to specify endpoint" && exit 1
[[ ! " ${AVAILABLE_LOCATIONS[@]}" =~ "${location}" ]] && show_help && echo "error: invalid location" && exit 1
[[ ! " ${AVAILABLE_PGTYPE[@]}" =~ "${pg_type}" ]] && show_help && echo "error: invalid PG instance type" && exit 1
[[ ! " ${AVAILABLE_ENDPOINTS[@]}" =~ "${endpoint}" ]] && show_help && echo "error: invalid endpoint" && exit 1

function infra_dv4_vcpus()
{
    [ -z "$with_infra" ] && echo 0 || echo 8
}

function infra_esv3_vcpus()
{
    [ -z "$with_infra" ] && echo 0 || echo 6
}

function need_public_ip()
{
    [ "$endpoint" = "public" ] && echo 1 || echo 0
}

function need_pg_vcpus_for()
{
    local pg_type=$(echo $1 | awk '{print tolower($0)}')
    local ha=$2

    local replica=1
    local vcpu=0
    [ "$ha" = "true" ] && replica=3

    case $pg_type in
      e2s_v3)
        vcpu=2
        ;;
      e4s_v3)
        vcpu=4
        ;;
      e8s_v3)
        vcpu=8
        ;;
      e16s_v3)
        vcpu=16
        ;;
      e20s_v3)
        vcpu=20
        ;;
      e32s_v3)
        vcpu=32
        ;;
      e48s_v3)
        vcpu=48
        ;;
      e64s_v3)
        vcpu=64
        ;;
      *)
        echo "invalid PG type"
        exit 1
        ;;
    esac

    echo $((vcpu*replica))
}

echo ""
echo "#######################"
echo "# Azure Information   #"
echo "#######################"
echo ""
# print azure information
az_subscrb=$(az account list -o table | grep -i true | awk '{print $(NF-2)}')
az account show -s $az_subscrb -o table

# call azure-cli to for usages of VM and Network
TMPDIR=$(mktemp -d)

function _cleanup {
  rm -rf "${TMPDIR}"
}
trap _cleanup EXIT
pushd "${TMPDIR}" > /dev/null 2>&1 || exit

TMP_VM_OUTPUT=$TMPDIR/vm_$$
TMP_NW_OUTPUT=$TMPDIR/ip_$$
TMP_SKU_OUTPUT=$TMPDIR/sku_$$
TMP_PROVIDER_OUTPUT=$TMPDIR/provider_$$
TMP_SUGGESTION=$TMPDIR/suggestions_$$
touch $TMP_SUGGESTION

function suggest()
{
    local what=$1
    local highlight=$2

    RED='\033[0;31m'
    GREEN='\033[0;32m'
    NC='\033[0m'
    if [ "$highlight" = 'alert' ]; then
        echo "${RED}${what}${NC}"
    else
        echo "${GREEN}${what}${NC}"
    fi
}

function store_suggestion()
{
    echo "$1" >> $TMP_SUGGESTION
}

#### Azure Subscription Checking
function validate_subscription() {
  state=$(echo $1 | jq .state | tr -d '"')
  if [ "$state" != "Enabled" ]; then
    store_suggestion "Azure subscription $az_subscrb state should be Enabled"
  fi
  tenant_id=$(echo $account | jq .tenantId | tr -d '"')
  store_suggestion "Make sure the tenant $tenant_id is the same as the one provided to EDB"
}

account=$(az account show -s $az_subscrb -o json)
validate_subscription "$account"

#### Azure User Role Assignment Checking
function validate_role_assignment() {
  user_name=$(echo $1 | jq .user.name | tr -d '"')
  count=$(az role assignment list --assignee $user_name --include-groups --include-inherited --role Owner -o json | jq length)
  if [ "$count" = "0" ]; then
    store_suggestion "Current user is $user_name. If you are going to do signup, you should have Owner role of the subscription $az_subscrb"
  fi
}

validate_role_assignment "$account"

#### Azure User Type Checking
function validate_user_type() {
  user_type=$(az ad signed-in-user show --query userType -o tsv)
  if [ "$user_type" != "Member" ]; then
    store_suggestion "Current user is a $user_type user, not Member user"
  fi
}

validate_user_type

#### Azure Provider Checking
REQUIRED_PROVIDER=(
  "Microsoft.ContainerInstance"
  "Microsoft.Compute"
  "Microsoft.ContainerService"
  "Microsoft.KeyVault"
  "Microsoft.ManagedIdentity"
  "Microsoft.Network"
  "Microsoft.OperationalInsights"
  "Microsoft.OperationsManagement"
  "Microsoft.Portal"
  "Microsoft.Storage"
)

function query_provider_list()
{
    az provider list -o table > $TMP_PROVIDER_OUTPUT
}

function provider_suggest()
{
    local st=$1
    local what=$2
    if [ "$st" = "Registered" ]; then
        suggest "$st" ok
    else
        store_suggestion "Provider '$what' is '$st'"
        suggest "$st" alert
    fi
}

echo ""
echo "#######################"
echo "# Provider            #"
echo "#######################"
echo ""
query_provider_list

# print the provider checking result
FMT="%-40s %-21s %-20b %-s\n"
printf "$FMT" "Namespace"                               "RegistrationPolicy"   "RegistrationState"   "ProviderAuthorizationConsentState"
printf "$FMT" "---------------------------------------" "--------------------" "-------------------" "-----------------------------------"
for required_provider in ${REQUIRED_PROVIDER[@]}; do
    col=($(< $TMP_PROVIDER_OUTPUT grep -w $required_provider))
    provider_namespace=${col[0]}
    registration_policy=${col[1]}
    registation_state=${col[2]}
    provider_authorization_consent_state=${col[3]}
    printf "$FMT" "$provider_namespace" "$registration_policy" $(provider_suggest "$registation_state" "$required_provider") "$provider_authorization_consent_state"
done

#### SKU Checking
function query_skus()
{
    az vm list-skus -l $location -o table > $TMP_SKU_OUTPUT
}

function get_sku_zone_for()
{
    local what=$1
    awk "/ $what /" $TMP_SKU_OUTPUT | awk '{print $4}'
}

function get_sku_restriction_for()
{
    local what=$1
    awk "/ $what /" $TMP_SKU_OUTPUT | awk '{$1=$2=$3=$4=""; print $0}' | xargs
}

function sku_suggest()
{
    local restriction=$1
    local sku=$2
    if [ "$restriction" = "None" ] || ([[ $restriction == *"type: Zone"* ]] && [ "$sku" = "Standard_D2_v4" ]); then
        suggest "None" ok
    else
        store_suggestion "virtualMachines SKU '$sku' has '$restriction'"
        suggest "$restriction" alert
    fi
}

echo ""
echo "#######################"
echo "# Virtual-Machine SKU #"
echo "#######################"
echo ""
query_skus $location
sku_restriction_d2v4=$(get_sku_restriction_for Standard_D2_v4)
sku_restriction_e2sv3=$(get_sku_restriction_for Standard_E2s_v3)

# print region Azure VM SKU checking result
FMT="%-17s %-22s %-23s %-8s %-b\n"
printf "$FMT" "ResourceType" "Locations" "Name" "Zones" "Restrictions"
printf "$FMT" "------------" "---------" "----" "-----" "------------"
printf "$FMT" "virtualMachines" "$location" "Standard_D2_v4" "$(get_sku_zone_for Standard_D2_v4)" "$(sku_suggest "$sku_restriction_d2v4" "Standard_D2_v4")"
printf "$FMT" "virtualMachines" "$location" "Standard_E2s_v3" "$(get_sku_zone_for Standard_E2s_v3)" "$(sku_suggest "$sku_restriction_e2sv3" "Standard_E2s_v3")"

#### Quota Limitation Checking
function query_all_usage()
{
    az vm list-usage -l $location -o table > $TMP_VM_OUTPUT
    az network list-usages -l $location -o table > $TMP_NW_OUTPUT
}

echo ""
echo "#######################"
echo "# Quota Limitation    #"
echo "#######################"
echo ""
query_all_usage $location

# parse VM usage
function get_vm_usage_for()
{
    local what=$1
    < $TMP_VM_OUTPUT grep "${what}" | awk '{print $(NF-1)" "$NF}'
}

regional_vcpus=($(get_vm_usage_for "Total Regional vCPUs"))
dsv2_vcpus=($(get_vm_usage_for "Standard DSv2 Family vCPUs"))
dv4_vcpus=($(get_vm_usage_for "Standard Dv4 Family vCPUs"))
esv3_vcpus=($(get_vm_usage_for "Standard ESv3 Family vCPUs"))

# parse network usage
function get_nw_usage_for()
{
    local what=$1
    < $TMP_NW_OUTPUT grep "${what}" | awk '{print $(NF-1)" "$NF}'
}

publicip_basic=($(get_nw_usage_for "Public IP Addresses - Basic"))
publicip_standard=($(get_nw_usage_for "Public IP Addresses - Standard"))

# calculate available resources
free_regional_vcpus=$((${regional_vcpus[1]} - ${regional_vcpus[0]}))
free_dv4_vcpus=$((${dv4_vcpus[1]} - ${dv4_vcpus[0]}))
free_esv3_vcpus=$((${esv3_vcpus[1]} - ${esv3_vcpus[0]}))
free_publicip_basic=$((${publicip_basic[1]} - ${publicip_basic[0]}))
free_publicip_standard=$((${publicip_standard[1]} - ${publicip_standard[0]}))

# calculate required resources
need_dv4_vcpus=$(infra_dv4_vcpus)
need_esv3_vcpus=$(($(need_pg_vcpus_for $pg_type $ha)+$(infra_esv3_vcpus)))
need_publicip_basic=$(need_public_ip)
need_publicip_standard=$(need_public_ip)

# calculate gap of "need - free"
gap_regional_vcpus=$((free_regional_vcpus - need_esv3_vcpus - need_dsv2_vcpus))
gap_dv4_vcpus=$((free_dv4_vcpus - need_dv4_vcpus))
gap_esv3_vcpus=$((free_esv3_vcpus - need_esv3_vcpus))
gap_publicip_basic=$((free_publicip_basic - need_publicip_basic))
gap_publicip_standard=$((free_publicip_standard - need_publicip_standard))

function quota_suggest()
{
    local gap=$1
    local resource=$2
    if [ "$gap" -le 0 ]; then
        store_suggestion "Resource '$resource' quota in '$location' has a gap of '$gap'"
        suggest "Need Increase" alert
    else
        suggest "OK" ok
    fi
}

# print region resources quota limitation checking result
FMT="%-32s %-8s %-8s %-11s %-8s %-11b\n"
printf "$FMT" "Resource" "Limit" "Used" "Available" "Gap" "Suggestion"
printf "$FMT" "--------" "-----" "----" "---------" "---" "----------"
printf "$FMT" "Total Regional vCPUs" ${regional_vcpus[1]} ${regional_vcpus[0]} ${free_regional_vcpus} $gap_regional_vcpus "$(quota_suggest $gap_regional_vcpus "Total Regional vCPUs")"
printf "$FMT" "Standard Dv4 Family vCPUs" ${dv4_vcpus[1]} ${dv4_vcpus[0]} ${free_dv4_vcpus} $gap_dv4_vcpus "$(quota_suggest $gap_dv4_vcpus "Standard Dv4 Family vCPUs")"
printf "$FMT" "Standard ESv3 Family vCPUs" ${esv3_vcpus[1]} ${esv3_vcpus[0]} ${free_esv3_vcpus} $gap_esv3_vcpus "$(quota_suggest $gap_esv3_vcpus "Standard ESv3 Family vCPUs")"
printf "$FMT" "Public IP Addresses - Basic" ${publicip_basic[1]} ${publicip_basic[0]} ${free_publicip_basic} $gap_publicip_basic "$(quota_suggest $gap_publicip_basic "Public IP Addresses - Basic")"
printf "$FMT" "Public IP Addresses - Standard" ${publicip_standard[1]} ${publicip_standard[0]} ${free_publicip_standard} $gap_publicip_standard "$(quota_suggest $gap_publicip_standard "Public IP Addresses - Standard")"


#### Print Final Suggestions Result
echo ""
echo "#######################"
echo "# Overall Suggestions #"
echo "#######################"
echo ""
cat $TMP_SUGGESTION

echo ""
echo "Please open a ticket to Azure if need to raise quota limit."
echo "Open https://portal.azure.com/#blade/Microsoft_Azure_Support/HelpAndSupportBlade/newsupportrequest for more info."
echo -e "You can also run \033[0;32maz support tickets create --help\033[0m for more examples."

