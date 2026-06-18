#!/usr/bin/env bash
# =============================================================================
# grant-rbac.sh
# Applies the 4 role assignments the lab needs after main.bicep has deployed.
# Run as a user with Owner / User Access Administrator on the subscription.
# Idempotent: az role assignment create returns success if the assignment exists.
# =============================================================================
set -euo pipefail

: "${RG_NAME:=rg-avd-lab}"
: "${VM_NAME:=avdsh-01}"
: "${APP_GROUP_NAME:=ag-avd-lab-desktop}"
: "${STORAGE_ACCOUNT_NAME:?Set STORAGE_ACCOUNT_NAME to your storage account name}"
: "${AVD_USERS_GROUP_OBJECT_ID:?Set AVD_USERS_GROUP_OBJECT_ID to the Entra group object id}"
: "${DEPLOYER_OBJECT_ID:?Set DEPLOYER_OBJECT_ID to your own Entra user object id}"

SUB_ID="$(az account show --query id -o tsv)"
RG_SCOPE="/subscriptions/${SUB_ID}/resourceGroups/${RG_NAME}"
VM_SCOPE="${RG_SCOPE}/providers/Microsoft.Compute/virtualMachines/${VM_NAME}"
APP_GROUP_SCOPE="${RG_SCOPE}/providers/Microsoft.DesktopVirtualization/applicationGroups/${APP_GROUP_NAME}"
STORAGE_SCOPE="${RG_SCOPE}/providers/Microsoft.Storage/storageAccounts/${STORAGE_ACCOUNT_NAME}"

echo "Granting Desktop Virtualization User on app group to AVD users group..."
az role assignment create \
  --role "Desktop Virtualization User" \
  --assignee-object-id "$AVD_USERS_GROUP_OBJECT_ID" \
  --assignee-principal-type Group \
  --scope "$APP_GROUP_SCOPE" \
  --output none || echo "  (already exists)"

echo "Granting Virtual Machine User Login on session host to AVD users group..."
az role assignment create \
  --role "Virtual Machine User Login" \
  --assignee-object-id "$AVD_USERS_GROUP_OBJECT_ID" \
  --assignee-principal-type Group \
  --scope "$VM_SCOPE" \
  --output none || echo "  (already exists)"

echo "Granting Storage File Data SMB Share Contributor on storage to AVD users group..."
az role assignment create \
  --role "Storage File Data SMB Share Contributor" \
  --assignee-object-id "$AVD_USERS_GROUP_OBJECT_ID" \
  --assignee-principal-type Group \
  --scope "$STORAGE_SCOPE" \
  --output none || echo "  (already exists)"

echo "Granting Storage File Data SMB Share Elevated Contributor on storage to deployer..."
az role assignment create \
  --role "Storage File Data SMB Share Elevated Contributor" \
  --assignee-object-id "$DEPLOYER_OBJECT_ID" \
  --assignee-principal-type User \
  --scope "$STORAGE_SCOPE" \
  --output none || echo "  (already exists)"

echo "RBAC grants complete."
