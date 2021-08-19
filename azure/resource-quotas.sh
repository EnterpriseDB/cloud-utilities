#!/bin/bash
set -e

function show_help()
{
    echo "Usage:"
    echo "   resource-quotas.sh --location <location> --pgtype <pg-type> [--ha] [--with-infra]"
}

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
    --pgtype)
      pg_type="$2"
      shift # past argument
      shift # past value
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

function infra_dsv2_vcpus()
{
    [ -z "$with_infra" ] && echo 0 || echo 6
}

function infra_esv3_vcpus()
{
    [ -z "$with_infra" ] && echo 0 || echo 6
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

# call azure-cli to for usages of VM and Network
TMP_VM_OUTPUT=/tmp/vm_$$
TMP_NW_OUTPUT=/tmp/ip_$$

function query_all_usage()
{
    az vm list-usage -l $location -o table > $TMP_VM_OUTPUT
    az network list-usages -l $location -o table > $TMP_NW_OUTPUT
}

query_all_usage $location

# parse VM usage
function get_vm_usage_for()
{
    local what=$1
    < $TMP_VM_OUTPUT grep "${what}" | awk '{print $(NF-1)" "$NF}'
}

regional_vcpus=($(get_vm_usage_for "Total Regional vCPUs"))
dsv2_vcpus=($(get_vm_usage_for "Standard DSv2 Family vCPUs"))
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
free_dsv2_vcpus=$((${dsv2_vcpus[1]} - ${dsv2_vcpus[0]}))
free_esv3_vcpus=$((${esv3_vcpus[1]} - ${esv3_vcpus[0]}))
free_publicip_basic=$((${publicip_basic[1]} - ${publicip_basic[0]}))
free_publicip_standard=$((${publicip_standard[1]} - ${publicip_standard[0]}))

# calculate required resources
need_dsv2_vcpus=$(infra_dsv2_vcpus)
need_esv3_vcpus=$(($(need_pg_vcpus_for $pg_type $ha)+$(infra_esv3_vcpus)))
need_publicip_basic=1
need_publicip_standard=1

# calculate gap of "need - free"
gap_regional_vcpus=$((free_regional_vcpus - need_esv3_vcpus - need_dsv2_vcpus))
gap_dsv2_vcpus=$((free_dsv2_vcpus - need_dsv2_vcpus))
gap_esv3_vcpus=$((free_esv3_vcpus - need_esv3_vcpus))
gap_publicip_basic=$((free_publicip_basic - need_publicip_basic))
gap_publicip_standard=$((free_publicip_standard - need_publicip_standard))

# print azure information
az_subscrb=$(az account list -o table | grep -i true | awk '{print $(NF-2)}')
az account show -s $az_subscrb -o table

echo ""

function suggestion()
{
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    NC='\033[0m'
    [ "$1" -le 0 ] && echo "${RED}Need Increase${NC}" || echo "${GREEN}OK${NC}"
}

# print result
FMT="%-32s %-8s %-8s %-11s %-8s %-11b\n"
printf "$FMT" "Resource" "Limit" "Used" "Available" "Gap" "Suggestion"
printf "$FMT" "--------" "-----" "----" "---------" "---" "----------"
printf "$FMT" "Total Regional vCPUs" ${regional_vcpus[1]} ${regional_vcpus[0]} ${free_regional_vcpus} $gap_regional_vcpus "$(suggestion $gap_regional_vcpus)"
printf "$FMT" "Standard DSv2 Family vCPUs" ${dsv2_vcpus[1]} ${dsv2_vcpus[0]} ${free_dsv2_vcpus} $gap_dsv2_vcpus "$(suggestion $gap_dsv2_vcpus)"
printf "$FMT" "Standard ESv3 Family vCPUs" ${esv3_vcpus[1]} ${esv3_vcpus[0]} ${free_esv3_vcpus} $gap_esv3_vcpus "$(suggestion $gap_esv3_vcpus)"
printf "$FMT" "Public IP Addresses - Basic" ${publicip_basic[1]} ${publicip_basic[0]} ${free_publicip_basic} $gap_publicip_basic "$(suggestion $gap_publicip_basic)"
printf "$FMT" "Public IP Addresses - Standard" ${publicip_standard[1]} ${publicip_standard[0]} ${free_publicip_standard} $gap_publicip_standard "$(suggestion $gap_publicip_standard)"
