#!/usr/bin/env bash
#vi: set ft=bash:

# This script will provision a cluster with the Terraform configuration provided.
# 
# **NOTE**: This was _not_ reviewed during the course and is provided as-is with
# no additional support.
#
# To learn more about Terraform, visit https://terraform.io.
TERRAFORM_DOCKER_IMAGE="carlosnunez/terraform:1.4.1"
AWS_DOCKER_IMAGE="amazon/aws-cli:2.2.9"
export AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY"
if ! test -z "$AWS_REGION"
then
  export AWS_REGION="$AWS_REGION"
fi
if ! test -z "$AWS_SESSION_TOKEN"
then
  export AWS_SESSION_TOKEN="$AWS_SESSION_TOKEN"
fi

terraform() {
  docker volume ls | grep -q "tfdata" || docker volume create tfdata
  docker run --rm -e "AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID" \
    -e "AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY" \
    -e "AWS_SESSION_TOKEN=${AWS_SESSION_TOKEN:-""}" \
    -e "AWS_REGION=$AWS_REGION" \
    -e "TF_IN_AUTOMATION=true" \
    -e "TF_DATA_DIR=/tfdata" \
    -v "$HOME/.kube:/root/.kube" \
    -v "$(dirname "$0")/infra:/work" \
    -v "tfdata:/tfdata" -w /work "$TERRAFORM_DOCKER_IMAGE" "$@"
}

aws() {
  docker run --rm -e "AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID" \
    -e "AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY" \
    -e "AWS_SESSION_TOKEN=$AWS_SESSION_TOKEN" \
    -e "AWS_REGION=$AWS_REGION" \
    -v "$(dirname "$0"):/work" \
    -w /work \
    "$AWS_DOCKER_IMAGE" "$@"
}

state_bucket_exists() {
  aws s3 ls "$TERRAFORM_S3_BUCKET" >/dev/null
}

initialize_terraform() {
  terraform init \
    -backend-config="bucket=$TERRAFORM_S3_BUCKET" \
    -backend-config="key=$TERRAFORM_S3_KEY"
}

delete_awslbic_policy() {
  aws iam list-policies |
    jq -r '.Policies[] | select(.PolicyName == "explore-california-awslbic-policy") | .Arn' |
    xargs -I {} aws iam delete-policy --policy-arn {}
}

delete_cluster() {
  terraform destroy -auto-approve
}

set -euo pipefail

TERRAFORM_S3_BUCKET="${TERRAFORM_S3_BUCKET?Please provide an S3 bucket to store state into.}"
TERRAFORM_S3_KEY="${TERRAFORM_S3_KEY?Please provide the key to use for state}"

if ! state_bucket_exists
then
  >&2 echo "ERROR: S3 bucket does not exist: $TERRAFORM_S3_BUCKET/$TERRAFORM_S3_KEY"
  exit 1
fi
initialize_terraform && delete_awslbic_policy && delete_cluster
