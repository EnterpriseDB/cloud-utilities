#!/bin/bash
#
# This script is used as a helper to follow an OAuth2 device code flow based
# procedure to authenticate to EDB Cloud service and obtain a token for
# accessing the EDB Cloud API.
#

BASE_URL=${BASE_URL:-https://portal.edbcloud.com}
TMPDIR=$(mktemp -d)

function _cleanup {
  rm -rf "${TMPDIR}"
}
trap _cleanup EXIT
pushd "${TMPDIR}" > /dev/null 2>&1 || exit

function show_help()
{
    echo "Get Tokens for EDB Cloud API"
    echo ""
    echo "Usage:"
    echo "  $0 [flags] [options]"
    echo ""
    echo "      -o, --format  json | plain         [optional] output format, default 'json'"
    echo "      -r, --refresh <refresh_token>      [optional] query for tokens again by the given refresh_token"
    echo "                                         this revokes and rotates the given refresh token, "
    echo "                                         please remember the newly returned refresh_token for"
    echo "                                         the next use"
    echo "      -h, --help                         show this help message"
    echo ""
    echo "Reference: https://www.enterprisedb.com/docs/edbcloud/latest/reference/ "
    echo ""
}

function check()
{
    # jq is needed
    hash jq > /dev/null 2>&1 || { echo "Please install jq on the system"; exit 1; }

    # format can only be plain or json
    AVAILABLE_FORMAT=(
	plain
        json
    )
    [[ ! " ${AVAILABLE_FORMAT[@]}" =~ "${format}" ]] && show_help && echo "error: invalid format" && exit 1
}

format="json"
# argument handling
POSITIONAL=()
while [[ $# -gt 0 ]]; do
  key="$1"

  case $key in
    -o|--format)
      format="$2"
      shift 2
      ;;
    -r|--refresh)
      REFRESH_TOKEN="$2"
      shift 2
      ;;
    -h|--help)
      show_help
      exit 0
      ;;
    *)    # unknown option
      POSITIONAL+=("$1") # save it in an array for later
      shift # past argument
      ;;
  esac
done

# 0. check mandatory dependency
check

# 1. Get Authentication Provider Relevant Information
curl -s ${BASE_URL}/api/v1/auth/provider > provider_resp || cat provider_resp || exit 1
# response sample
# {
#   "clientId": "pM8PRguGtW9yVnrsvrvpaPyyeS9fVvFh",
#   "issuerUri": "https://auth.edbcloud.com",
#   "scope": "openid profile email offline_access",
#   "audience": "https://portal.edbcloud.com/api"
# }

CLIENT_ID=$(< provider_resp jq -r .clientId)
AUTH_SERVER=$(< provider_resp jq -r .issuerUri)
SCOPE=$(< provider_resp jq -r .scope)
AUDIENCE=$(< provider_resp jq -r .audience)

# 2. Choose method for obtaining the token
#   - for the first time use, follow the device code flow
#   - if you have a refresh_token, use it

function get_by_device_code()
{
    curl -s --request POST \
      --url "$AUTH_SERVER/oauth/device/code" \
      --header "content-type: application/x-www-form-urlencoded" \
      --data "client_id=$CLIENT_ID" \
      --data "scope=$SCOPE" \
      --data "audience=$AUDIENCE" > code_resp || cat code_resp || exit 1
    # response sample
    # {
    #   "device_code": "KEOY2_5YjuVsRuIrrR-aq5gs",
    #   "user_code": "HHHJ-MMSZ",
    #   "verification_uri": "https://auth.edbcloud.com/activate",
    #   "expires_in": 900,
    #   "interval": 5,
    #   "verification_uri_complete": "https://auth.edbcloud.com/activate?user_code=HHHJ-MMSZ"
    # }
    DEVICE_CODE=$(< code_resp jq -r .device_code)
    USER_CODE=$(< code_resp jq -r .user_code)
    VERIFICATION_URI_COMPLETE=$(< code_resp jq -r .verification_uri_complete)

    # Guide the user to finish the AuthN flow on Web Browser

    echo "Please login to ${VERIFICATION_URI_COMPLETE} with your EDB Cloud account"

    while ! [ "${input}" = "y" ]; do
      read -p "Have you finished the login successfully? (y/N) " input
    done

    # Polling for the Token
    curl -s --request POST \
      --url "$AUTH_SERVER/oauth/token" \
      --header "content-type: application/x-www-form-urlencoded" \
      --data "grant_type=urn:ietf:params:oauth:grant-type:device_code" \
      --data "device_code=$DEVICE_CODE" \
      --data "client_id=$CLIENT_ID" > token_resp || cat token_resp || exit 1
    # Response Sample
    # {
    #   "access_token": "eyJhbGc.......1Qtkaw2fyho",
    #   "id_token": "eyJhbGci.......FBra7tA",
    #   "refresh_token": "v1.MTvuZpu.......sbiionEhtTw",
    #   "scope": "openid profile email offline_access",
    #   "expires_in": 86400,
    #   "token_type": "Bearer"
    # }
    #
    # error Response Sample
    # {
    #   "error": "access_denied",
    #   "error_description": "..."
    # }
}

function get_by_refresh_token()
{
    curl -s --request POST \
     --url "$AUTH_SERVER/oauth/token" \
     --header "content-type: application/x-www-form-urlencoded" \
     --data "grant_type=refresh_token" \
     --data "client_id=$CLIENT_ID" \
     --data "refresh_token=$REFRESH_TOKEN" > token_resp || cat token_resp || exit 1
}

function exchange_edbcloud_token()
{
    local raw_token=$1
    curl -s --request POST \
     --url "$BASE_URL/api/v1/auth/token" \
     --header "content-type: application/json" \
     --data "{\"token\":\"$raw_token\"}" > edbcloud_token_resp || cat edbcloud_token_resp || exit 1
    # Response Sample
    # {
    #   "token": "eyJhbGciOifQ.eyJhdWQiONjxxxxxxxxxxxxx"
    # }
    #
    # error Response Sample
    # {
    #   "error": {
    #      "status": 500,
    #      "message": "Internal Server Error",
    #      "details": "failed to get EDB Cloud token",
    #      "reference": "upmrid/wTb-9lB08A0U6Jpr06688/ByASWaOlHzB3fUp-BBXZe",
    #      "source": "API"
    #   }
    # }
    #
}

function handle_http_error()
{
    local resp=$1
    local error_key=$2
    local error_detail_key=$3

    local error=$(< $resp jq -r $error_key)
    local description=$(< $resp jq -r $error_detail_key)

    if ! [ "${ERROR}" = 'null' ] && ! [ "${ERROR}" = "" ]; then
        if [ "$format" = 'json' ]; then
            < $resp jq .
        else
            echo "error: $error"
            echo "details: $description"
        fi
        exit 1
    fi
}

# choose proper method to get the token
if [ -z "${REFRESH_TOKEN}" ]; then
    get_by_device_code
else
    get_by_refresh_token
fi
handle_http_error token_resp .error .error_description

# exchange the raw access_token to EDB Cloud token
# and handle the error
exchange_edbcloud_token $(< token_resp jq -r .access_token)
handle_http_error edbcloud_token_resp .error.message .error.details

function print_result()
{
    # Always substitute the access_token with the one exchanged
    # from EDB Cloud portal API
    if [ "$format" = 'json' ]; then
        < token_resp jq ".access_token=$(< edbcloud_token_resp jq .token) | del(.id_token)"
    else
        # Parse token
        ACCESS_TOKEN=$(< edbcloud_token_resp jq -r .token)
        REFRESH_TOKEN=$(< token_resp jq -r .refresh_token)
        EXPIRES_IN=$(< token_resp jq -r .expires_in)

        echo "####### Access Token ################"
        echo $ACCESS_TOKEN
        echo ""

        echo "####### Refresh Token ###############"
        echo $REFRESH_TOKEN
        echo ""

        #echo "#######   ID Token    ###############"
        #echo $ID_TOKEN
        #echo ""

        echo "#####   Expires In Seconds ##########"
        echo $EXPIRES_IN
        echo ""
    fi
}
print_result
