#!/usr/bin/env bash
set -euo pipefail
RG_NAME="${RG_NAME:-rg-avd-lab}"
SA_NAME="${SA_NAME:-$STORAGE_ACCOUNT_NAME}"

# Optional hygiene: de-register the Entra Kerberos SPN before the RG goes away
if [ -n "${SA_NAME:-}" ]; then
  az storage account update \
    --name "$SA_NAME" \
    --resource-group "$RG_NAME" \
    --enable-files-aadkerb false 2>/dev/null || true
fi

az group delete --name "$RG_NAME" --yes --no-wait
echo "Deletion submitted. Poll with: az group show --name $RG_NAME"
