#!/usr/bin/env bash
#
# Copyright 2022 EnterpriseDB Corporation
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

# This script is used to create an IAM role and and IAM policy with enough
# permissions in your AWS account for handling the BigAnimal managed
# service, and returing its ARN in a "ba-passport.json".
#
# What it does:
#   - assume you have an AWS profile configured to work with the AWS CLI
#   - configured your AWS profile to work with the selected account
#   - create an IAM policy following the PoLP (Principle of Least Privilege)
#   - create an IAM role attaching the previously created IAM policy
#   - write the IAM role ARN into a local file named "ba-passport.json"
#   - request for needed service quota increases if asked to
#
# it finally outputs the:
#   - IAM policy ARN
#   - IAM role ARN
#   - AWS account ID where those resources have been created
#   - The new Service Quota that have been requested
# The "ba-passport.json" file content will be used later on with the BigAnimal CLI
# to connect your AWS account to your BigAnimal cloud account.
#
# For more details, please refer to
#  https://www.enterprisedb.com/docs/edbcloud/latest/getting_started/02_connect_cloud_account
#
set -e
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'
[ "${BASH_VERSINFO:-0}" -lt 4 ] && echo -e "${RED}This script does not support Bash version 3 and below!${NC}" && show_help && exit 1
CURRENT_PATH=$(pwd)

# Default values for resources naming
policy_name="biganimal-policy"
role_name="biganimal-role"
account=""
biganimal_account_id=""
external_id=""
region=""
increase_quota=false
declare -A quota_increases
aws_used_service_quota_codes=("ec2" "vpc" "elasticloadbalancing")
declare -A quota_names

TMPDIR=$(mktemp -d)
function cleanup {
  rm -rf "${TMPDIR}"
}
trap cleanup EXIT
pushd "${TMPDIR}" >/dev/null || exit

show_help()
{
  echo "Required permissions:"
  echo "  arn:aws:iam::aws:policy/IAMFullAccess"
  echo "  arn:aws:iam::aws:policy/ServiceQuotasFullAccess"
  echo "  or equivalents like"
  echo "  arn:aws:iam::aws:policy/AdministratorAccess"
  echo "Required tools:"
  echo "  jq"
  echo "Usage:"
  echo -e "  ${GREEN}$0 -a ACCOUNT_ID -b BIGANIMAL_ACCOUNT_ID -e EXTERNAL_ID [options]${NC}"
  echo ""
  echo "Options:"
  echo "  -a, --account:           Your AWS account ID that will be used by BigAnimal."
  echo "  -b, --biganimal-account: The AWS account ID provided by BigAnimal (should be a 12 chars numeric string)."
  echo "  -e, --external-id:       The AWS external ID provided by BigAnimal (should be a 16 chars alphanumeric string)."
  echo "  -p, --policy-name:       The name of the IAM policy (defaults to 'biganimal-policy')."
  echo "  -r, --role-name:         The name of the IAM role (defaults to 'biganimal-role')."
  echo "  -q, --increase-quotas:   Create tickets to request Service Quota increases if needed (defaults to false)."
  echo "  -g, --region:            The name of the AWS region in which ask for service quota increases (defaults to your AWS CLI profile)"
  echo "  -h, --help:              Show this help."
  echo ""
  echo "Examples:"
  echo "    $0 -a 123456789012 -b 987654321098 -e aA1bB2cC3dD4eE5f"
  echo "    $0 -a 123456789012 -b 987654321098 -e aA1bB2cC3dD4eE5f -p \"my_policy_name\" -r \"my_role_name\" -q"
}

check()
{
  #### Check AWS CLI version
  check_aws_version
  # jq is required.
  hash jq > /dev/null 2>&1 || { show_help; echo -e "${RED}Error: please install jq on the system${NC}"; }
  check_account
  check_biganimal_account_id
  check_external_id
  check_increase_quotas
}

version() { echo "$@" | awk -F. '{ printf("%d%03d%03d%03d\n", $1,$2,$3,$4); }'; }

check_aws_version()
{
  fullcliversion=$(aws --version)
  cliversionstripped=${fullcliversion% Python*}
  cliversion=${cliversionstripped#*/}
  if [[ "$AWS_EXECUTION_ENV" == "CloudShell" ]]; then
    echo -e "${GREEN}Run AWS create-policy-and-role with aws-cli ${cliversion} in AWS CloudShell${NC}"
  else
    [ "$(version "$cliversion")" -lt "$(version "2.3.0")" ] && echo -e "${RED}Error: upgrade aws-cli to 2.3.0 or later${NC}" && exit 1
    echo -e "${GREEN}Run AWS create-policy-and-role with aws-cli ${cliversion}${NC}"
  fi
}

check_account()
{
  if [[ "${account}" == "" ]]; then
    echo -e "${RED}Error: missing -a, --account to specify the AWS account ID${NC}"
    show_help
    exit 1
  fi
  # check that the aws cli is configured to work with the given account and we have access to
  set +e
  current_account=$(aws sts get-caller-identity --no-cli-pager --query 'Account' --output text)
  if [ $? -ne 0 ]; then
    echo -e "${RED}Error while checking AWS credentials/profile configuration, please login/configure your AWS CLI session/profile${NC}"
    show_help
    exit 1
  fi
  set -e
  if [[ ! "${current_account}" == "$account" ]]; then
    echo -e "${RED}Error: AWS CLI not configured to work with the requested account $account!${NC}"
    echo -e "${RED}The configured account ID is ${current_account}!${NC}"
    show_help
    exit 1
  fi
}

check_biganimal_account_id()
{
  if [[ "${biganimal_account_id}" == "" ]]; then
    echo -e "${RED}Error: missing -b, --biganimal-account to specify the AWS account ID provided by BigAnimal${NC}"
    show_help
    exit 1
  fi
  if [[ ! "$biganimal_account_id" =~ ^[0-9]{12}$ ]]; then
    echo -e "${RED}Error: the specified biganimal-account is wrong, it should be a 12 chars numeric string!${NC}"
    show_help
    exit 1
  fi
}

check_external_id()
{
  if [[ "${external_id}" == "" ]]; then
    echo -e "${RED}Error: missing -e, --external-id to specify the AWS external ID provided by BigAnimal${NC}"
    show_help
    exit 1
  fi
  if [[ ! "$external_id" =~ ^[a-zA-Z0-9]{16}$ ]]; then
    echo -e "${RED}Error: the specified external-id is wrong, it should be a 16 chars alphanumeric string!${NC}"
    show_help
    exit 1
  fi
}

check_increase_quotas()
{
  if [[ "$increase_quota" == "true" ]]; then
    if [ -s "${CURRENT_PATH}/ba-preflight.json" ]; then
      set +e
      jq empty "${CURRENT_PATH}"/ba-preflight.json
      [ $? -ne 0 ] && echo -e "${RED}Error while checking ${CURRENT_PATH}/ba-preflight.json, it doesn't have a valid JSON content${NC}" \
        && show_help && exit 1
      set -e
      for key in $(jq -r 'keys[]' "${CURRENT_PATH}"/ba-preflight.json); do
        quota_increases[${key}]=$(jq -r ".\"$key\"" "${CURRENT_PATH}"/ba-preflight.json)
      done
    else
      echo -e "${RED}Error: can't find ba-preflight.json in ${CURRENT_PATH}!${NC}"
      show_help
      exit 1
    fi
  fi
}

while [[ $# -gt 0 ]]; do
  key="$1"

  case $key in
    -h|--help)
      show_help
      exit 0
      ;;
    -a|--account)
      account="$2"
      shift 2
      ;;
    -b|--biganimal-account)
      biganimal_account_id="$2"
      shift 2
      ;;
    -e|--external-id)
      external_id="$2"
      shift 2
      ;;
    -p|--policy-name)
      policy_name="$2"
      shift 2
      ;;
    -r|--role-name)
      role_name="$2"
      shift 2
      ;;
    -q|--increase-quotas)
      increase_quota=true
      shift
      ;;
    -g|--region)
      region="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

create_iam_policy()
{
  # IAM Policy
  biganimal_policy=$(cat <<EOF
{"Version":"2012-10-17","Statement":[{"Action":["dynamodb:DeleteItem","dynamodb:DescribeContinuousBackups","dynamodb:DescribeTable","dynamodb:GetItem","dynamodb:PutItem","ec2:AllocateAddress","ec2:AssociateRouteTable","ec2:AttachInternetGateway","ec2:AuthorizeSecurityGroupEgress","ec2:AuthorizeSecurityGroupIngress","ec2:CreateEgressOnlyInternetGateway","ec2:CreateInternetGateway","ec2:CreateNatGateway","ec2:CreateNetworkAcl","ec2:CreateNetworkAclEntry","ec2:CreateRoute","ec2:CreateRouteTable","ec2:CreateSecurityGroup","ec2:CreateSubnet","ec2:CreateTags","ec2:CreateVpc","ec2:CreateVpcEndpoint","ec2:DeleteEgressOnlyInternetGateway","ec2:DeleteInternetGateway","ec2:DeleteNatGateway","ec2:DeleteNetworkAcl","ec2:DeleteNetworkAclEntry","ec2:DeleteRoute","ec2:DeleteRouteTable","ec2:DeleteSecurityGroup","ec2:DeleteSubnet","ec2:DeleteVpc","ec2:DeleteVpcEndpoints","ec2:Describe*","ec2:DetachInternetGateway","ec2:DisassociateRouteTable","ec2:Get*","ec2:ListSnapshotsInRecycleBin","ec2:ModifySubnetAttribute","ec2:ModifyVpcAttribute","ec2:ReleaseAddress","ec2:ReplaceNetworkAclAssociation","ec2:ReplaceRoute","ec2:RevokeSecurityGroupEgress","ec2:RevokeSecurityGroupIngress","ec2:SearchLocalGatewayRoutes","ec2:SearchTransitGatewayRoutes","ecs:Describe*","ecs:List*","eks:CreateAddon","eks:CreateCluster","eks:CreateNodegroup","eks:DeleteAddon","eks:DeleteCluster","eks:DeleteNodegroup","eks:Describe*","eks:List*","eks:TagResource","eks:UntagResource","eks:UpdateAddon","eks:UpdateNodegroupConfig","iam:AttachRolePolicy","iam:CreateOpenIDConnectProvider","iam:CreatePolicy","iam:CreateRole","iam:DeleteOpenIDConnectProvider","iam:DeletePolicy","iam:DeleteRole","iam:DeleteRolePolicy","iam:DetachRolePolicy","iam:GetAccountSummary","iam:GetOpenIDConnectProvider","iam:GetPolicy","iam:GetPolicyVersion","iam:GetRole","iam:GetRolePolicy","iam:ListAccessKeys","iam:ListAttachedRolePolicies","iam:ListEntitiesForPolicy","iam:ListInstanceProfilesForRole","iam:ListInstanceProfileTags","iam:ListMFADevices","iam:ListMFADeviceTags","iam:ListOpenIDConnectProviders","iam:ListOpenIDConnectProviderTags","iam:ListPolicies","iam:ListPoliciesGrantingServiceAccess","iam:ListPolicyTags","iam:ListPolicyVersions","iam:ListRolePolicies","iam:ListRoles","iam:ListRoleTags","iam:ListSAMLProviders","iam:ListSAMLProviderTags","iam:ListServerCertificates","iam:ListServerCertificateTags","iam:ListServiceSpecificCredentials","iam:ListSigningCertificates","iam:ListSSHPublicKeys","iam:ListVirtualMFADevices","iam:PutRolePolicy","iam:TagOpenIDConnectProvider","iam:TagPolicy","iam:TagRole","iam:UntagOpenIDConnectProvider","iam:UpdateRole","kms:CreateGrant","kms:CreateKey","kms:DescribeKey","kms:EnableKeyRotation","kms:GetKeyPolicy","kms:GetKeyRotationStatus","kms:ListResourceTags","kms:ScheduleKeyDeletion","kms:TagResource","logs:CreateLogGroup","logs:CreateLogStream","logs:DeleteLogGroup","logs:DescribeLogGroups","logs:GetLogGroupFields","logs:ListTagsLogGroup","logs:PutLogEvents","logs:PutRetentionPolicy","logs:TagLogGroup","logs:UntagLogGroup","s3:CreateBucket","s3:DeleteBucket","s3:DeleteBucketPolicy","s3:DeleteObject","s3:DescribeJob","s3:Get*","s3:List*","s3:PutBucketOwnershipControls","s3:PutBucketPolicy","s3:PutBucketPublicAccessBlock","s3:PutBucketTagging","s3:PutBucketVersioning","s3:PutEncryptionConfiguration","s3:PutObject","sts:DecodeAuthorizationMessage"],"Effect":"Allow","Resource":"*","Sid":"BigAnimalBasePolicy"},{"Action":["secretsmanager:*"],"Effect":"Allow","Resource":"arn:aws:secretsmanager:*:*:secret:BA*","Sid":"BigAnimalSecretsPolicy"}]}
EOF
  )
  echo "$biganimal_policy" > "${TMPDIR}"/biganimal_policy.json

  # create IAM policy using aws-cli
  echo -e "Creating AWS IAM policy ${GREEN}${policy_name}${NC} within AWS account ${GREEN}${account}${NC}..."
  aws iam create-policy --policy-name "$policy_name" --policy-document file://"${TMPDIR}"/biganimal_policy.json \
    > "${TMPDIR}"/biganimal_createpolicy_output.json
}

create_iam_role()
{
  # IAM Trust Policy
  biganimal_trustpolicy=$(cat <<EOF
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":"sts:AssumeRole","Principal":{"AWS":"${biganimal_account_id}"},"Condition":{"StringEquals":{"sts:ExternalId":"${external_id}"}}}]}
EOF
  )
  echo "$biganimal_trustpolicy" > "${TMPDIR}"/biganimal_trustpolicy.json

  # create IAM role using aws-cli
  echo -e "Creating AWS IAM role ${GREEN}${role_name}${NC} within AWS account ${GREEN}${account}${NC}..."
  aws iam create-role --role-name "$role_name" --assume-role-policy-document file://"${TMPDIR}"/biganimal_trustpolicy.json \
    > "${TMPDIR}"/biganimal_createrole_output.json
}

increase_quotas()
{
  if [[ "$increase_quota" == "true" ]]; then
    if [[ "${region}" == "" ]]; then
      region=$(aws configure get region)
    fi
    # Create AWS support tickets to increase the needed quotas
    for quota_code in "${!quota_increases[@]}"; do
      for service_code in "${aws_used_service_quota_codes[@]}"; do
        quotas=$(aws service-quotas list-service-quotas --service-code "$service_code" --query "Quotas[*].QuotaCode" --output text)
        if [[ $quotas == *"$quota_code"* ]]; then
          aws service-quotas request-service-quota-increase --service-code "$service_code" --quota-code "$quota_code" \
            --desired-value "${quota_increases["$quota_code"]}" --region "$region" > "${TMPDIR}"/biganimal_quotaincrease_output.json
          quota_name=$(jq -r '.RequestedQuota.QuotaName' "${TMPDIR}"/biganimal_quotaincrease_output.json)
          quota_names["$quota_code"]=$quota_name
        fi
      done
    done
  fi
}

save_result()
{
  policy_arn=$(jq -r '.Policy.Arn' "${TMPDIR}"/biganimal_createpolicy_output.json)
  role_arn=$(jq -r '.Role.Arn' "${TMPDIR}"/biganimal_createrole_output.json)
  echo ""
  echo "######################################################"
  echo -e "# Script Results running on AWS account ${GREEN}${account}${NC} #"
  echo "######################################################"
  echo ""
  echo -e "Created AWS IAM policy ${GREEN}${policy_name}${NC} ARN is: ${GREEN}${policy_arn}${NC}"
  echo -e "Created AWS IAM role ${GREEN}${role_name}${NC} ARN is: ${GREEN}${role_arn}${NC}"
  if [[ "$increase_quota" == "true" ]]; then
    for quota_code in "${!quota_increases[@]}"; do
      echo -e "Requested AWS Service quota increase for ${GREEN}${quota_names["$quota_code"]}${NC}, quota requested is: ${GREEN}${quota_increases["$quota_code"]}${NC}"
    done
    echo -e "You can check your ${GREEN}Quota request history${NC} on the AWS Console here:"
    echo -e "${GREEN}https://${region}.console.aws.amazon.com/servicequotas/home/requests?region=${region}#${NC}"
  fi
  # exporting JSON "ba-passport.json" that will be used by BigAnimal CLI
  echo "{\"${role_name}\":\"${role_arn}\"}" > "$CURRENT_PATH"/ba-passport.json
}

check
create_iam_policy
create_iam_role
increase_quotas
save_result
