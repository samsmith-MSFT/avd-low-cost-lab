// =============================================================================
// main.bicepparam
// Parameter file for AVD personal low-cost learning lab.
//
// Required runtime overrides (pass via --parameters on the CLI):
//   adminPassword            (secure)
//   avdUsersGroupObjectId    (the Entra group object id for AVD users)
//   deployerObjectId         (your own Entra user object id)
//   aadTenantDomain          (e.g. contoso.onmicrosoft.com)
//   aadTenantId              (Entra tenant GUID)
//   storageAccountName       (3-24 lowercase alphanumeric, globally unique)
// =============================================================================
using 'main.bicep'

// ---- Region & naming -------------------------------------------------------
param location                  = 'westcentralus'
param resourceGroupName         = 'rg-avd-lab'
param logAnalyticsWorkspaceName = 'law-avd-lab'
param nsgName                   = 'nsg-avd-snet-sh'
param vnetName                  = 'vnet-avd-lab'
param hostPoolName              = 'hp-avd-lab'
param appGroupName              = 'ag-avd-lab-desktop'
param workspaceName             = 'ws-avd-lab'
param fileShareName             = 'fslogix-profiles'
param sessionHostName           = 'avdsh-01'
param vmSize                    = 'Standard_D2s_v5'

// ---- Auto-shutdown ---------------------------------------------------------
param shutdownTime              = '1800'                  // 6:00 PM
param shutdownTimeZone          = 'Central Standard Time'

// ---- VM credentials --------------------------------------------------------
param adminUsername             = 'avdadmin'
param adminPassword             = ''                       // SUPPLY ON CLI

// ---- Identity / auth (SUPPLY ALL ON CLI) -----------------------------------
param storageAccountName        = ''                       // SUPPLY ON CLI
param avdUsersGroupObjectId     = ''                       // SUPPLY ON CLI
param deployerObjectId          = ''                       // SUPPLY ON CLI
param aadTenantDomain           = ''                       // SUPPLY ON CLI
param aadTenantId               = ''                       // SUPPLY ON CLI

// ---- Tags ------------------------------------------------------------------
param tags = {
  workload: 'avd-lab'
  environment: 'sandbox'
  costcenter: 'personal'
}
