# AVD Lab — Validated Gotcha Checklist

Last validated 2026-06-18 against first-party Microsoft Learn docs. Every item is cited.

## Identity choice (Entra ID-join vs AD DS)

- ✅ **AD DS / AADDS is NOT required for AVD session hosts.** Entra-only join is fully supported per [AVD prerequisites](https://learn.microsoft.com/azure/virtual-desktop/prerequisites#identity).
- ⚠️ **All session hosts in a host pool must use the same join type.** No mixing Entra-joined and domain-joined VMs in one pool. Per [Microsoft Entra joined session hosts](https://learn.microsoft.com/azure/virtual-desktop/azure-ad-joined-session-hosts).
- ⚠️ **OS requirement for cloud-only users:** Windows 11/10 single-session or multi-session 2004+, or Server 2022/2019. Win11 24H2 multi-session AVD image qualifies.

## Required at the VM level (Entra join)

- ✅ **System-assigned managed identity REQUIRED on the VM BEFORE AADLoginForWindows extension runs.** Per [VM sign-in with Entra ID](https://learn.microsoft.com/entra/identity/devices/howto-vm-sign-in-azure-ad-windows#requirements). The AVM VM module fires both in parallel — race window — must declare `managedIdentities: { systemAssigned: true }` in the same module call.
- ✅ **AADLoginForWindows extension settings should be EMPTY (`settings: null` or omitted).** The AVM module strips `settings: {}` to `null` automatically. `mdmId` is OPT-IN for Intune autopilot enrollment — do NOT pass it unless you actually want Intune enrollment.
- ⚠️ **AVM module defaults `typeHandlerVersion: '2.0'` with auto-upgrade ON.** Runtime gets latest 2.x (e.g. 2.2.0.0). To pin: `extensionAadJoinConfig: { enabled: true, typeHandlerVersion: '2.0', autoUpgradeMinorVersion: false }`.
- 🔴 **Tenant CA policies can block device registration.** If a Conditional Access policy requires MFA for "all users" or "all apps", it can block the system MI's device registration call. Exclude the **Azure Windows VM Sign-In** app (`372140e0-b3b7-4226-8ef9-d57986796201`) from any MFA CA policy.

## Required at the host pool level

- ✅ **Custom RDP property `targetisaadjoined:i:1`** is mandatory for any client that isn't Entra-joined to the same tenant (web client, macOS, iOS, Android, BYOD Windows).
- ✅ **Custom RDP property `enablerdsaadauth:i:1`** for SSO via Entra (highly recommended).
- ✅ **RBAC: assign `Virtual Machine User Login` role to the AVD users group on the VM (or RG/sub).** Required for Entra-joined hosts only; AD DS-joined hosts don't need it. Per [AVD AAD-joined session hosts → Assign user access](https://learn.microsoft.com/azure/virtual-desktop/azure-ad-joined-session-hosts#assign-user-access-to-host-pools).

## Required for FSLogix on Azure Files (cloud-only AADKERB)

- ✅ **Region must support cloud-only per-group RBAC for AADKERB.** Per the [supported regions list](https://learn.microsoft.com/azure/storage/files/storage-files-identity-auth-hybrid-identities-enable). In US public cloud, ONLY `westcentralus` and only Premium tier qualifies.
- 🔴 **MANDATORY: Grant admin consent to the storage account's auto-created Entra app.** Without it, users can't get Entra ID tokens for the storage account. Entra Portal → App registrations → `[Storage Account] <sa>.file.core.windows.net` → API permissions → Grant admin consent.
- 🔴 **MANDATORY for cloud-only: Add `kdc_enable_cloud_group_sids` to the storage app's manifest tags.** Without it, Entra excludes cloud-only group SIDs from Kerberos tickets → user has no group membership → access denied.
- 🔴 **MANDATORY if any MFA CA policy is in place: Exclude the storage app from CA MFA policies.** Otherwise FSLogix mount fails with `System error 1327`.
- ⚠️ **Optional check: `application management policies` blocking symmetric key addition.** If your tenant has a policy blocking symmetric key addition on SPs, grant exception for `Storage Resource Provider` (app ID `a6aa9161-5291-40bb-8c5c-923b567bee3b`).
- ✅ **VM-side registry keys (set via Custom Script Extension, group policy, or Intune):**
  - `HKLM\SYSTEM\CurrentControlSet\Control\Lsa\Kerberos\Parameters\CloudKerberosTicketRetrievalEnabled = 1`
  - `HKLM\Software\Policies\Microsoft\AzureADAccount\LoadCredKeyFromProfile = 1` (FSLogix roaming compat)
  - `HKLM\SOFTWARE\FSLogix\Profiles\Enabled = 1`
  - `HKLM\SOFTWARE\FSLogix\Profiles\VHDLocations = \\<sa>.file.core.windows.net\<share>`

## Order-of-operations matrix (bicep can't do these — manual pre/post)

| Step | Where | When |
|---|---|---|
| Create Entra security group `AVD-Lab-Users` | Entra portal or `az ad group create` | Pre-deploy |
| Add yourself to the group | Entra portal or `az ad group member add` | Pre-deploy |
| Audit CA policies, exclude `Azure Windows VM Sign-In` (372140e0-...) | Entra portal → Conditional Access | Pre-deploy |
| Grant admin consent to `[Storage Account] <sa>.file.core.windows.net` app | Entra portal → App registrations → API permissions | **Post-deploy** (the app is auto-created on Bicep apply) |
| Add `kdc_enable_cloud_group_sids` to that app's manifest | Entra portal → App manifest tags | **Post-deploy** |
| Exclude that app from MFA CA policies | Entra portal → Conditional Access | **Post-deploy** |

## Common error codes (validated)

| Error | Decoded | Real cause |
|---|---|---|
| `0x801C002D` / `-2145648595` | `DSREG_E_DEVICE_AUTHENTICATION_ERROR — GetTenantId failed` | System MI missing on VM (extension can't find tenant via IMDS) |
| `0x801C0072` / `-2145648526` | `DSREG_E_USER_HASNO_HOMETENANT` | Most likely: a CA policy is blocking the MI's device registration call. Other possibilities: corrupted prior join state, tenant-level device-registration restriction. NOT an mdmId issue (the AVM module strips empty mdmId; `mdmId: "0"` workarounds don't help). |
| `0x801C0072` / `-2145648574` | `DSREG_E_MSI_TENANTID_UNAVAILABLE` | Same root as 0x801C002D; MI not on VM or IMDS not returning tenant info |
| `0x80190005` / `-2145648607` | `DSREG_AUTOJOIN_DISC_FAILED` | Network blocked: `enterpriseregistration.windows.net` not reachable from session host |
| `0x3000047` | AVD client connect error | Session host status not Available — usually means DomainJoinedCheck failed (host not actually joined) |
| `System error 1327` | "Account restrictions" on FSLogix mount | MFA CA policy not excluded from storage account app |

## What killed the first deploy (avd-lab-20260618)

| Hypothesis | Evidence | Verdict |
|---|---|---|
| Missing MI | First deploy had `managedIdentities` unset; extension reported `GetTenantId failed` | ✅ Real, fixed by setting `systemAssigned: true` |
| mdmId required | Extension v2.2.0.0 once reported `mdmId not found` after an out-of-band reinstall | ❌ False; was an artifact of removing-and-readding the extension partial state. AVM module handles correctly. |
| MDM-Intune enrollment failing | Tried `mdmId: "0"` and Intune app ID — both gave same `0x801C0072` | ❌ False; mdmId isn't the issue |
| Region not supporting AADKERB | We picked `westcentralus` knowing this | ✅ Real constraint, design accommodated it |
| Tenant CA policy blocking device registration | NOT YET VALIDATED — likely the root cause | ⚠️ Needs validation by Sam in Entra portal |

## Next-deploy pre-flight (must all be ✅ before `az deployment sub create`)

- [ ] **Conditional Access audit:** any policies targeting "All apps" + MFA? Exclude `Azure Windows VM Sign-In` (372140e0-...). [Entra portal](https://entra.microsoft.com/#view/Microsoft_AAD_ConditionalAccess/ConditionalAccessBlade/~/Policies)
- [ ] **AVD-Lab-Users Entra group exists**, Sam is a member, objectId captured
- [ ] **Storage account name** chosen, globally unique, ≤24 lowercase alphanumeric
- [ ] **MI ordering verified:** bicep sets `managedIdentities: { systemAssigned: true }` in the same module call as the AADLogin extension
- [ ] **AADLogin extension settings:** empty (`settings: {}` or omitted) — do NOT pass `mdmId`
- [ ] **Post-deploy admin consent script ready:** for the storage account's auto-created Entra app
