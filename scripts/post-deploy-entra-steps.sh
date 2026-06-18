#!/usr/bin/env bash
# =============================================================================
# post-deploy-entra-steps.sh
# Reminds the operator of the 3 Entra portal-only steps that Bicep cannot do.
# These are MANDATORY for FSLogix on Azure Files with cloud-only Entra Kerberos.
# =============================================================================
set -euo pipefail

: "${STORAGE_ACCOUNT_NAME:?Set STORAGE_ACCOUNT_NAME}"

cat <<EOF

==============================================================================
POST-DEPLOY ENTRA STEPS (manual, browser-only)
==============================================================================

Open Microsoft Entra admin center:
  https://entra.microsoft.com/#view/Microsoft_AAD_RegisteredApps/ApplicationsListBlade

Find the auto-created storage account application:
  Display name: [Storage Account] ${STORAGE_ACCOUNT_NAME}.file.core.windows.net

For that app, do all three of these:

1. GRANT ADMIN CONSENT
   - App > API permissions
   - Click "Grant admin consent for <your-tenant>"
   - Confirm. The 3 permissions (openid, profile, User.Read) flip to Granted.

2. ENABLE CLOUD-ONLY GROUPS SUPPORT
   - App > Manifest
   - Find the "tags" array (top-level)
   - Add the string: "kdc_enable_cloud_group_sids"
   - Save.

3. EXCLUDE FROM MFA CONDITIONAL ACCESS
   - https://entra.microsoft.com/#view/Microsoft_AAD_ConditionalAccess/ConditionalAccessBlade
   - For any policy that targets "All cloud apps" and requires MFA, edit it:
   - Cloud apps or actions > Exclude > select the storage account app
   - Save.

Without these three steps, FSLogix mounts will fail with System error 1327.
==============================================================================
EOF