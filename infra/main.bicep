// =============================================================================
// main.bicep
// Scope  : subscription
// Purpose: Azure Virtual Desktop personal low-cost learning lab
// Region : westcentralus (only US region supporting per-group RBAC for
//          cloud-only Entra Kerberos on Azure Files - Premium tier only)
// =============================================================================
targetScope = 'subscription'

// ---------------------------------------------------------------------------
// Parameters
// ---------------------------------------------------------------------------
@description('Azure region for all resources.')
param location string = 'westcentralus'

@description('Resource group name.')
param resourceGroupName string = 'rg-avd-lab'

@description('Log Analytics workspace name.')
param logAnalyticsWorkspaceName string = 'law-avd-lab'

@description('Network security group name.')
param nsgName string = 'nsg-avd-snet-sh'

@description('Virtual network name.')
param vnetName string = 'vnet-avd-lab'

@description('Host pool name.')
param hostPoolName string = 'hp-avd-lab'

@description('Application group name.')
param appGroupName string = 'ag-avd-lab-desktop'

@description('Workspace name.')
param workspaceName string = 'ws-avd-lab'

@description('Storage account name (3-24 lowercase alphanumeric, globally unique).')
@minLength(3)
@maxLength(24)
param storageAccountName string

@description('File share name for FSLogix profiles.')
param fileShareName string = 'fslogix-profiles'

@description('Session host VM name (max 15 chars for Windows).')
@maxLength(15)
param sessionHostName string = 'avdsh-01'

@description('Session host VM size.')
param vmSize string = 'Standard_D2s_v5'

@description('Object ID of the pre-existing Entra security group for AVD users.')
param avdUsersGroupObjectId string

@description('Object ID of the principal running this deployment.')
param deployerObjectId string

@description('Entra tenant primary domain name (e.g. contoso.onmicrosoft.com).')
param aadTenantDomain string

@description('Entra tenant GUID.')
param aadTenantId string

@description('Local admin username for the session host VM.')
param adminUsername string = 'avdadmin'

@description('Local admin password for the session host VM.')
@secure()
param adminPassword string

@description('Auto-shutdown time in HHMM 24-hr format.')
param shutdownTime string = '1800'

@description('Time zone for auto-shutdown schedule.')
param shutdownTimeZone string = 'Central Standard Time'

@description('Tags applied to all resources.')
param tags object = {
  workload: 'avd-lab'
  environment: 'sandbox'
  costcenter: 'personal'
}

// ---------------------------------------------------------------------------
// Variables
// ---------------------------------------------------------------------------
// Built-in role definition IDs (subscription scope)
var roleDesktopVirtualizationUser = '1d18fff3-a72a-46b5-b4a9-0b38a3cd7e63'
var roleVirtualMachineUserLogin   = 'fb879df8-f326-4884-b1cf-06f3ad86be52'
var roleSmbShareContributor       = '0c867c2a-1d8c-454a-a3db-ab2ea1bdc8bb'
var roleSmbShareElevatedContrib   = 'a7264617-510b-434b-a828-9731dc254ea7'

// FSLogix configuration script - loaded at compile time, tokenized, base64-encoded
var fslogixScriptRaw = loadTextContent('scripts/configure-fslogix.ps1')
var fslogixScript    = replace(replace(fslogixScriptRaw, '__STORAGE_ACCOUNT__', storageAccountName), '__FILE_SHARE__', fileShareName)
var fslogixScriptB64 = base64(fslogixScript)
// Decode-and-execute wrapper: PowerShell decodes the UTF-8 base64 string back to
// script text, then runs it as a script block. Avoids backslash-escape hell in Bicep.
var fslogixCommand = 'powershell -ExecutionPolicy Bypass -NoProfile -Command "$s = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String(\'${fslogixScriptB64}\')); Invoke-Expression $s"'

// ---------------------------------------------------------------------------
// Resource Group
// ---------------------------------------------------------------------------
resource rg 'Microsoft.Resources/resourceGroups@2024-11-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

// ---------------------------------------------------------------------------
// 1. Log Analytics Workspace
// ---------------------------------------------------------------------------
module law 'br/public:avm/res/operational-insights/workspace:0.15.1' = {
  scope: rg
  name: 'deploy-law'
  params: {
    name: logAnalyticsWorkspaceName
    location: location
    skuName: 'PerGB2018'
    dataRetention: 30
    tags: tags
  }
}

// ---------------------------------------------------------------------------
// 2. NSG - deny all inbound (AVD uses reverse-connect, no inbound required)
// ---------------------------------------------------------------------------
module nsg 'br/public:avm/res/network/network-security-group:0.5.3' = {
  scope: rg
  name: 'deploy-nsg'
  params: {
    name: nsgName
    location: location
    tags: tags
    securityRules: [
      {
        name: 'DenyAllInbound'
        properties: {
          priority: 4096
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
          description: 'AVD reverse-connect does not require inbound rules.'
        }
      }
    ]
    diagnosticSettings: [
      {
        name: 'diag-nsg-to-law'
        workspaceResourceId: law.outputs.resourceId
      }
    ]
  }
}

// ---------------------------------------------------------------------------
// 3. VNet + session-host subnet
// ---------------------------------------------------------------------------
module vnet 'br/public:avm/res/network/virtual-network:0.9.0' = {
  scope: rg
  name: 'deploy-vnet'
  params: {
    name: vnetName
    location: location
    tags: tags
    addressPrefixes: [
      '10.50.0.0/16'
    ]
    subnets: [
      {
        name: 'snet-sessionhosts'
        addressPrefix: '10.50.1.0/24'
        networkSecurityGroupResourceId: nsg.outputs.resourceId
      }
    ]
  }
}

// ---------------------------------------------------------------------------
// 4. AVD Host Pool  (module is orphaned in AVM but functional)
// ---------------------------------------------------------------------------
module hostPool 'br/public:avm/res/desktop-virtualization/host-pool:0.8.1' = {
  scope: rg
  name: 'deploy-hostpool'
  params: {
    name: hostPoolName
    location: location
    tags: tags
    hostPoolType: 'Pooled'
    loadBalancerType: 'BreadthFirst'
    maxSessionLimit: 10
    validationEnvironment: false
    managementType: 'Standard'
    tokenValidityLength: 'PT8H'
    // Custom RDP properties: enable Entra auth path + multimon + clipboard,
    // disable redirection bits not needed for a lab
    customRdpProperty: 'audiocapturemode:i:1;audiomode:i:0;drivestoredirect:s:;redirectclipboard:i:1;redirectcomports:i:0;redirectprinters:i:0;redirectsmartcards:i:0;screen mode id:i:2;enablerdsaadauth:i:1;targetisaadjoined:i:1;'
    diagnosticSettings: [
      {
        name: 'diag-hp-to-law'
        workspaceResourceId: law.outputs.resourceId
        logCategoriesAndGroups: [
          { categoryGroup: 'allLogs' }
        ]
      }
    ]
  }
}

// ---------------------------------------------------------------------------
// 5. AVD Application Group (Desktop)  (module is orphaned in AVM but functional)
// ---------------------------------------------------------------------------
module appGroup 'br/public:avm/res/desktop-virtualization/application-group:0.4.2' = {
  scope: rg
  name: 'deploy-appgroup'
  params: {
    name: appGroupName
    location: location
    tags: tags
    applicationGroupType: 'Desktop'
    hostpoolName: hostPool.outputs.name
    roleAssignments: [
      {
        principalId: avdUsersGroupObjectId
        principalType: 'Group'
        roleDefinitionIdOrName: roleDesktopVirtualizationUser
      }
    ]
    diagnosticSettings: [
      {
        name: 'diag-ag-to-law'
        workspaceResourceId: law.outputs.resourceId
        logCategoriesAndGroups: [
          { categoryGroup: 'allLogs' }
        ]
      }
    ]
  }
}

// ---------------------------------------------------------------------------
// 6. AVD Workspace - registers the application group
// ---------------------------------------------------------------------------
module avdWorkspace 'br/public:avm/res/desktop-virtualization/workspace:0.9.2' = {
  scope: rg
  name: 'deploy-workspace'
  params: {
    name: workspaceName
    location: location
    tags: tags
    friendlyName: 'AVD Lab Workspace'
    applicationGroupReferences: [
      appGroup.outputs.resourceId
    ]
    diagnosticSettings: [
      {
        name: 'diag-ws-to-law'
        workspaceResourceId: law.outputs.resourceId
        logCategoriesAndGroups: [
          { categoryGroup: 'allLogs' }
        ]
      }
    ]
  }
}

// ---------------------------------------------------------------------------
// 7. Storage Account - FSLogix profiles
//    Premium Files (FileStorage / Premium_LRS) - required for per-group RBAC
//    on cloud-only Entra Kerberos in westcentralus
// ---------------------------------------------------------------------------
module storageAccount 'br/public:avm/res/storage/storage-account:0.32.1' = {
  scope: rg
  name: 'deploy-storage'
  params: {
    name: storageAccountName
    location: location
    tags: tags
    kind: 'FileStorage'
    skuName: 'Premium_LRS'
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
    publicNetworkAccess: 'Enabled'
    // ---- AADKERB (Entra Kerberos) identity-based authentication ----
    azureFilesIdentityBasedAuthentication: {
      directoryServiceOptions: 'AADKERB'
      activeDirectoryProperties: {
        domainName: aadTenantDomain
        domainGuid: aadTenantId
      }
    }
    // ---- FSLogix profile share (Premium, 100 GiB minimum) ----
    fileServices: {
      shares: [
        {
          name: fileShareName
          shareQuota: 100
          accessTier: 'Premium'
          enabledProtocols: 'SMB'
        }
      ]
      diagnosticSettings: [
        {
          name: 'diag-fileSvc-to-law'
          workspaceResourceId: law.outputs.resourceId
        }
      ]
    }
    // ---- RBAC ----
    roleAssignments: [
      {
        principalId: avdUsersGroupObjectId
        principalType: 'Group'
        roleDefinitionIdOrName: roleSmbShareContributor
      }
      {
        principalId: deployerObjectId
        principalType: 'User'
        roleDefinitionIdOrName: roleSmbShareElevatedContrib
      }
    ]
    diagnosticSettings: [
      {
        name: 'diag-sa-to-law'
        workspaceResourceId: law.outputs.resourceId
      }
    ]
  }
}

// ---------------------------------------------------------------------------
// 8. Session host VM
//    - NIC, Entra ID join, host pool registration, FSLogix CSE, auto-shutdown
//      all handled by the VM module's native extension parameters.
// ---------------------------------------------------------------------------
module sessionHost 'br/public:avm/res/compute/virtual-machine:0.22.2' = {
  scope: rg
  name: 'deploy-sessionhost'
  params: {
    name: sessionHostName
    location: location
    tags: tags
    vmSize: vmSize
    osType: 'Windows'
    availabilityZone: -1
    adminUsername: adminUsername
    adminPassword: adminPassword
    imageReference: {
      publisher: 'microsoftwindowsdesktop'
      offer: 'windows-11'
      sku: 'win11-24h2-avd'
      version: 'latest'
    }
    osDisk: {
      caching: 'ReadWrite'
      createOption: 'FromImage'
      deleteOption: 'Delete'
      diskSizeGB: 128
      managedDisk: {
        storageAccountType: 'StandardSSD_LRS'
      }
    }
    nicConfigurations: [
      {
        name: '${sessionHostName}-nic-01'
        deleteOption: 'Delete'
        ipConfigurations: [
          {
            name: 'ipconfig01'
            subnetResourceId: '${vnet.outputs.resourceId}/subnets/snet-sessionhosts'
            privateIPAllocationMethod: 'Dynamic'
          }
        ]
      }
    ]
    extensionAadJoinConfig: {
      enabled: true
      settings: {}
    }
    extensionHostPoolRegistration: {
      enabled: true
      hostPoolName: hostPool.outputs.name
      registrationInfoToken: hostPool.outputs.registrationToken!
      modulesUrl: 'https://wvdportalstorageblob.blob.${environment().suffixes.storage}/galleryartifacts/Configuration_09-08-2022.zip'
      configurationFunction: 'Configuration.ps1\\AddSessionHost'
    }
    extensionCustomScriptConfig: {
      name: 'configure-fslogix'
      settings: {
        commandToExecute: fslogixCommand
      }
    }
    autoShutdownConfig: {
      status: 'Enabled'
      dailyRecurrenceTime: shutdownTime
      timeZone: shutdownTimeZone
      notificationSettings: {
        status: 'Disabled'
      }
    }
    roleAssignments: [
      {
        principalId: avdUsersGroupObjectId
        principalType: 'Group'
        roleDefinitionIdOrName: roleVirtualMachineUserLogin
      }
    ]
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------
output resourceGroupName        string = rg.name
output resourceGroupId          string = rg.id
output lawResourceId            string = law.outputs.resourceId
output vnetResourceId           string = vnet.outputs.resourceId
output hostPoolResourceId       string = hostPool.outputs.resourceId
output appGroupResourceId       string = appGroup.outputs.resourceId
output workspaceResourceId      string = avdWorkspace.outputs.resourceId
output storageAccountResourceId string = storageAccount.outputs.resourceId
output sessionHostResourceId    string = sessionHost.outputs.resourceId
output sessionHostName          string = sessionHostName
output adminUsername            string = adminUsername
output fslogixSharePath         string = '\\\\${storageAccountName}.file.${environment().suffixes.storage}\\${fileShareName}'
