#!/usr/bin/env bash
# =============================================================================
# deploy.sh
# Deploys the AVD lab. Runs main.bicep, then applies role assignments
# via grant-rbac.sh (split out because ARM RBAC cache delays can roll back
# inline role assignments on a fresh User Access Administrator grant).
# =============================================================================
set -euo pipefail

RG_LOCATION="${RG_LOCATION:-westcentralus}"
TEMPLATE="infra/main.bicep"
PARAMS="infra/main.bicepparam"

: "${STORAGE_ACCOUNT_NAME:?Set STORAGE_ACCOUNT_NAME (3-24 lowercase alphanumeric, globally unique)}"
: "${AVD_USERS_GROUP_OBJECT_ID:?Set AVD_USERS_GROUP_OBJECT_ID to the objectId of your AVD-Lab-Users Entra group}"
: "${AAD_TENANT_DOMAIN:?Set AAD_TENANT_DOMAIN (e.g. yourdomain.onmicrosoft.com)}"

DEPLOYER_OBJECT_ID="${DEPLOYER_OBJECT_ID:-$(az ad signed-in-user show --query id -o tsv)}"
AAD_TENANT_ID="${AAD_TENANT_ID:-$(az account show --query tenantId -o tsv)}"

if [ -z "${ADMIN_PASSWORD:-}" ]; then
  read -rsp "VM local admin password: " ADMIN_PASSWORD; echo
fi

echo "==== Deploying main.bicep ===="
az deployment sub create \
  --name "avd-lab-$(date +%Y%m%d-%H%M%S)" \
  --location "$RG_LOCATION" \
  --template-file "$TEMPLATE" \
  --parameters "$PARAMS" \
  --parameters \
    storageAccountName="$STORAGE_ACCOUNT_NAME" \
    avdUsersGroupObjectId="$AVD_USERS_GROUP_OBJECT_ID" \
    deployerObjectId="$DEPLOYER_OBJECT_ID" \
    aadTenantDomain="$AAD_TENANT_DOMAIN" \
    aadTenantId="$AAD_TENANT_ID" \
    adminPassword="$ADMIN_PASSWORD" \
  --output table

echo ""
echo "==== Applying RBAC grants ===="
"$(dirname "$0")/grant-rbac.sh"

echo ""
echo "==== Deployment complete ===="
echo "Connect to your desktop at: https://client.wvd.microsoft.com"