# =============================================================================
# configure-fslogix.ps1
# Configures FSLogix profile container settings + Entra Kerberos client config
# on an AVD session host. Run during VM provisioning via Custom Script Extension.
#
# Tokens (replaced at deploy time by the calling Bicep):
#   __STORAGE_ACCOUNT__   storage account name (e.g. stavdlabxxxxx)
#   __FILE_SHARE__        file share name (e.g. fslogix-profiles)
# =============================================================================
$ErrorActionPreference = 'Stop'

$storageAccount = '__STORAGE_ACCOUNT__'
$fileShare      = '__FILE_SHARE__'
$vhdLocation    = "\\$storageAccount.file.core.windows.net\$fileShare"

Write-Host "Configuring FSLogix profiles -> $vhdLocation"

# --- FSLogix Profiles registry config ---------------------------------------
$fslogixKey = 'HKLM:\SOFTWARE\FSLogix\Profiles'
if (-not (Test-Path $fslogixKey)) {
    New-Item -Path $fslogixKey -Force | Out-Null
}
Set-ItemProperty -Path $fslogixKey -Name Enabled        -Type DWord  -Value 1
Set-ItemProperty -Path $fslogixKey -Name VHDLocations   -Type String -Value $vhdLocation
Set-ItemProperty -Path $fslogixKey -Name DeleteLocalProfileWhenVHDShouldApply -Type DWord -Value 1
Set-ItemProperty -Path $fslogixKey -Name FlipFlopProfileDirectoryName        -Type DWord -Value 1
Set-ItemProperty -Path $fslogixKey -Name VolumeType                          -Type String -Value 'vhdx'
Set-ItemProperty -Path $fslogixKey -Name SizeInMBs                           -Type DWord -Value 30000

# --- Entra Kerberos client config (cloud-only KDC ticket retrieval) ---------
$kerbKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\Kerberos\Parameters'
if (-not (Test-Path $kerbKey)) {
    New-Item -Path $kerbKey -Force | Out-Null
}
Set-ItemProperty -Path $kerbKey -Name CloudKerberosTicketRetrievalEnabled -Type DWord -Value 1

$aadAcctKey = 'HKLM:\Software\Policies\Microsoft\AzureADAccount'
if (-not (Test-Path $aadAcctKey)) {
    New-Item -Path $aadAcctKey -Force | Out-Null
}
Set-ItemProperty -Path $aadAcctKey -Name LoadCredKeyFromProfile -Type DWord -Value 1

Write-Host "FSLogix + Entra Kerberos client config complete."
