<#
.SYNOPSIS
    Lists delegated permissions (OAuth2PermissionGrants) and application permissions (AppRoleAssignments).

.PARAMETER DelegatedPermissions
    If set, will return delegated permissions. If neither this switch nor the ApplicationPermissions switch is set,
    both application and delegated permissions will be returned.

.PARAMETER ApplicationPermissions
    If set, will return application permissions. If neither this switch nor the DelegatedPermissions switch is set,
    both application and delegated permissions will be returned.

.PARAMETER UserProperties
    The list of properties of user objects to include in the output. Defaults to DisplayName only.

.PARAMETER ServicePrincipalProperties
    The list of properties of service principals (i.e. apps) to include in the output. Defaults to DisplayName only.

.PARAMETER ShowProgress
    Whether or not to display a progress bar when retrieving application permissions (which could take some time).

.PARAMETER PrecacheSize
    The number of users to pre-load into a cache. For tenants with over a thousand users,
    increasing this may improve performance of the script.

.EXAMPLE
    PS C:\> .\Get-AzureADPSPermissions.ps1 | Export-Csv -Path "permissions.csv" -NoTypeInformation
    Generates a CSV report of all permissions granted to all apps.

.EXAMPLE
    PS C:\> .\Get-AzureADPSPermissions.ps1 -ApplicationPermissions -ShowProgress | Where-Object { $_.Permission -eq "Directory.Read.All" }
    Get all apps which have application permissions for Directory.Read.All.

.EXAMPLE
    PS C:\> .\Get-AzureADPSPermissions.ps1 -UserProperties @("DisplayName", "UserPrincipalName", "Mail") -ServicePrincipalProperties @("DisplayName", "AppId")
    Gets all permissions granted to all apps and includes additional properties for users and service principals.

.NOTES
    Original script done by @psignoret - https://gist.github.com/psignoret/41793f8c6211d2df5051d77ca3728c09
    Adapted to MS Graph by @acap4z
#>

[CmdletBinding()]
param(
    [switch] $DelegatedPermissions,

    [switch] $ApplicationPermissions,

    [string[]] $UserProperties = @("DisplayName"),

    [string[]] $ServicePrincipalProperties = @("DisplayName"),

    [switch] $ShowProgress,

    [int] $PrecacheSize = 999
)

# Get tenant details to test that Connect-MgGraph has been called
$tenant_details = Get-MgOrganization
if (!($tenant_details)){
	return
}

Write-Verbose ("TenantId: {0}, InitialDomain: {1}" -f `
                $tenant_details.Id, `
                ($tenant_details.VerifiedDomains | Where-Object { $_.IsInitial }).Name)

# Permission lookup table
# Extracted from: https://learn.microsoft.com/en-us/graph/permissions-reference#all-permissions-and-ids
$permission_lookup = @{
"ebfcd32b-babb-40f4-a14b-42706e83bd28" = "AccessReview.Read.All";
"d07a8cc0-3d51-4b77-b3b0-32704d1f69fa" = "AccessReview.Read.All";
"e4aa47b9-9a69-4109-82ed-36ec70d85ff1" = "AccessReview.ReadWrite.All";
"ef5f7d5c-338f-44b0-86c3-351f46c8bb5f" = "AccessReview.ReadWrite.All";
"5af8c3f5-baca-439a-97b0-ea58a435e269" = "AccessReview.ReadWrite.Membership";
"18228521-a591-40f1-b215-5fad4488c117" = "AccessReview.ReadWrite.Membership";
"9084c10f-a2d6-4713-8732-348def50fe02" = "Acronym.Read.All";
"8c0aed2c-0c61-433d-b63c-6370ddc73248" = "Acronym.Read.All";
"3361d15d-be43-4de6-b441-3c746d05163d" = "AdministrativeUnit.Read.All";
"134fd756-38ce-4afd-ba33-e9623dbe66c2" = "AdministrativeUnit.Read.All";
"7b8a2d34-6b3f-4542-a343-54651608ad81" = "AdministrativeUnit.ReadWrite.All";
"5eb59dd3-1da2-4329-8733-9dabdc435916" = "AdministrativeUnit.ReadWrite.All";
"af2819c9-df71-4dd3-ade7-4d7c9dc653b7" = "Agreement.Read.All";
"2f3e6f8c-093b-4c57-a58b-ba5ce494a169" = "Agreement.Read.All";
"ef4b5d93-3104-4664-9053-a5c49ab44218" = "Agreement.ReadWrite.All";
"c9090d00-6101-42f0-a729-c41074260d47" = "Agreement.ReadWrite.All";
"0b7643bb-5336-476f-80b5-18fbfbc91806" = "AgreementAcceptance.Read";
"a66a5341-e66e-4897-9d52-c2df58c2bfb9" = "AgreementAcceptance.Read.All";
"d8e4ec18-f6c0-4620-8122-c8b1f2bf400e" = "AgreementAcceptance.Read.All";
"e03cf23f-8056-446a-8994-7d93dfc8b50e" = "Analytics.Read";
"1b6ff35f-31df-4332-8571-d31ea5a4893f" = "APIConnectors.Read.All";
"b86848a7-d5b1-41eb-a9b4-54a4e6306e97" = "APIConnectors.Read.All";
"c67b52c5-7c69-48b6-9d48-7b3af3ded914" = "APIConnectors.ReadWrite.All";
"1dfe531a-24a6-4f1b-80f4-7a0dc5a0a171" = "APIConnectors.ReadWrite.All";
"88e58d74-d3df-44f3-ad47-e89edf4472e4" = "AppCatalog.Read.All";
"e12dae10-5a57-4817-b79d-dfbec5348930" = "AppCatalog.Read.All";
"1ca167d5-1655-44a1-8adf-1414072e1ef9" = "AppCatalog.ReadWrite.All";
"dc149144-f292-421e-b185-5953f2e98d7f" = "AppCatalog.ReadWrite.All";
"3db89e36-7fa6-4012-b281-85f3d9d9fd2e" = "AppCatalog.Submit";
"c79f8feb-a9db-4090-85f9-90d820caa0eb" = "Application.Read.All";
"9a5d68dd-52b0-4cc2-bd40-abcf44ac3a30" = "Application.Read.All";
"bdfbf15f-ee85-4955-8675-146e8e5296b5" = "Application.ReadWrite.All";
"1bfefb4e-e0b5-418b-a88f-73c46d2cc8e9" = "Application.ReadWrite.All";
"18a4783c-866b-4cc7-a460-3d5e5662c884" = "Application.ReadWrite.OwnedBy";
"84bccea3-f856-4a8a-967b-dbe0a3d53a64" = "AppRoleAssignment.ReadWrite.All";
"06b708a9-e830-4db3-a914-8e69da51d44f" = "AppRoleAssignment.ReadWrite.All";
"104a7a4b-ca76-4677-b7e7-2f4bc482f381" = "AttackSimulation.Read.All";
"93283d0a-6322-4fa8-966b-8c121624760d" = "AttackSimulation.Read.All";
"27608d7c-2c66-4cad-a657-951d575f5a60" = "AttackSimulation.ReadWrite.All";
"e125258e-8c8a-42a8-8f55-ab502afa52f3" = "AttackSimulation.ReadWrite.All";
"e4c9e354-4dc5-45b8-9e7c-e1393b0b1a20" = "AuditLog.Read.All";
"b0afded3-3588-46d8-8b3d-9842eff778da" = "AuditLog.Read.All";
"57b030f1-8c35-469c-b0d9-e4a077debe70" = "AuthenticationContext.Read.All";
"381f742f-e1f8-4309-b4ab-e3d91ae4c5c1" = "AuthenticationContext.Read.All";
"ba6d575a-1344-4516-b777-1404f5593057" = "AuthenticationContext.ReadWrite.All";
"a88eef72-fed0-4bf7-a2a9-f19df33f8b83" = "AuthenticationContext.ReadWrite.All";
"2bf6d319-dfca-4c22-9879-f88dcfaee6be" = "BillingConfiguration.ReadWrite.All";
"9e8be751-7eee-4c09-bcfd-d64f6b087fd8" = "BillingConfiguration.ReadWrite.All";
"b27a61ec-b99c-4d6a-b126-c4375d08ae30" = "BitlockerKey.Read.All";
"5a107bfc-4f00-4e1a-b67e-66451267bc68" = "BitlockerKey.ReadBasic.All";
"7f36b48e-542f-4d3b-9bcb-8406f0ab9fdb" = "Bookings.Manage.All";
"33b1df99-4b29-4548-9339-7a7b83eaeebc" = "Bookings.Read.All";
"6e98f277-b046-4193-a4f2-6bf6a78cd491" = "Bookings.Read.All";
"948eb538-f19d-4ec5-9ccc-f059e1ea4c72" = "Bookings.ReadWrite.All";
"02a5a114-36a6-46ff-a102-954d89d9ab02" = "BookingsAppointment.ReadWrite.All";
"9769393e-5a9f-4302-9e3d-7e018ecb64a7" = "BookingsAppointment.ReadWrite.All";
"98b17b35-f3b1-4849-a85f-9f13733002f0" = "Bookmark.Read.All";
"be95e614-8ef3-49eb-8464-1c9503433b86" = "Bookmark.Read.All";
"fb9be2b7-a7fc-4182-aec1-eda4597c43d5" = "BrowserSiteLists.Read.All";
"c5ee1f21-fc7f-4937-9af0-c91648ff9597" = "BrowserSiteLists.Read.All";
"83b34c85-95bf-497b-a04e-b58eca9d49d0" = "BrowserSiteLists.ReadWrite.All";
"8349ca94-3061-44d5-9bfb-33774ea5e4f9" = "BrowserSiteLists.ReadWrite.All";
"d16480b2-e469-4118-846b-d3d177327bee" = "BusinessScenarioConfig.Read.All";
"c47e7b6e-d6f1-4be9-9ffd-1e00f3e32892" = "BusinessScenarioConfig.Read.OwnedBy";
"acc0fc4d-2cd6-4194-8700-1768d8423d86" = "BusinessScenarioConfig.Read.OwnedBy";
"755e785b-b658-446f-bb22-5a46abd029ea" = "BusinessScenarioConfig.ReadWrite.All";
"b3b7fcff-b4d4-4230-bf6f-90bd91285395" = "BusinessScenarioConfig.ReadWrite.OwnedBy";
"bbea195a-4c47-4a4f-bff2-cba399e11698" = "BusinessScenarioConfig.ReadWrite.OwnedBy";
"25b265c4-5d34-4e44-952d-b567f6d3b96d" = "BusinessScenarioData.Read.OwnedBy";
"6c0257fd-cffe-415b-8239-2d0d70fdaa9c" = "BusinessScenarioData.Read.OwnedBy";
"19932d57-2952-4c60-8634-3655c79fc527" = "BusinessScenarioData.ReadWrite.OwnedBy";
"f2d21f22-5d80-499e-91cc-0a8a4ce16f54" = "BusinessScenarioData.ReadWrite.OwnedBy";
"465a38f9-76ea-45b9-9f34-9e8b0d4b0b42" = "Calendars.Read";
"798ee544-9d2d-430c-a058-570e29e34338" = "Calendars.Read";
"2b9c4092-424d-4249-948d-b43879977640" = "Calendars.Read.Shared";
"662d75ba-a364-42ad-adee-f5f880ea4878" = "Calendars.ReadBasic";
"8ba4a692-bc31-4128-9094-475872af8a53" = "Calendars.ReadBasic.All";
"1ec239c2-d7c9-4623-a91a-a9775856bb36" = "Calendars.ReadWrite";
"ef54d2bf-783f-4e0f-bca1-3210c0444d99" = "Calendars.ReadWrite";
"12466101-c9b8-439a-8589-dd09ee67e8e9" = "Calendars.ReadWrite.Shared";
"a2611786-80b3-417e-adaa-707d4261a5f0" = "CallRecord-PstnCalls.Read.All";
"45bbb07e-7321-4fd7-a8f6-3ff27e6a81c8" = "CallRecords.Read.All";
"a7a681dc-756e-4909-b988-f160edc6655f" = "Calls.AccessMedia.All";
"284383ee-7f6e-4e40-a2a8-e85dcb029101" = "Calls.Initiate.All";
"4c277553-8a09-487b-8023-29ee378d8324" = "Calls.InitiateGroupCall.All";
"f6b49018-60ab-4f81-83bd-22caeabfed2d" = "Calls.JoinGroupCall.All";
"fd7ccf6b-3d28-418b-9701-cd10f5cd2fd4" = "Calls.JoinGroupCallAsGuest.All";
"101147cf-4178-4455-9d58-02b5c164e759" = "Channel.Create";
"f3a65bd4-b703-46df-8f7e-0174fea562aa" = "Channel.Create";
"cc83893a-e232-4723-b5af-bd0b01bcfe65" = "Channel.Delete.All";
"6a118a39-1227-45d4-af0c-ea7b40d210bc" = "Channel.Delete.All";
"9d8982ae-4365-4f57-95e9-d6032a4c0b87" = "Channel.ReadBasic.All";
"59a6b24b-4225-4393-8165-ebaec5f55d7a" = "Channel.ReadBasic.All";
"2eadaff8-0bce-4198-a6b9-2cfc35a30075" = "ChannelMember.Read.All";
"3b55498e-47ec-484f-8136-9013221c06a9" = "ChannelMember.Read.All";
"0c3e411a-ce45-4cd1-8f30-f99a3efa7b11" = "ChannelMember.ReadWrite.All";
"35930dcf-aceb-4bd1-b99a-8ffed403c974" = "ChannelMember.ReadWrite.All";
"2b61aa8a-6d36-4b2f-ac7b-f29867937c53" = "ChannelMessage.Edit";
"767156cb-16ae-4d10-8f8b-41b657c8c8c8" = "ChannelMessage.Read.All";
"7b2449af-6ccd-4f4d-9f78-e550c193f0d1" = "ChannelMessage.Read.All";
"5922d31f-46c8-4404-9eaf-2117e390a8a4" = "ChannelMessage.ReadWrite";
"ebf0f66e-9fb1-49e4-a278-222f76911cf4" = "ChannelMessage.Send";
"4d02b0cc-d90b-441f-8d82-4fb55c34d6bb" = "ChannelMessage.UpdatePolicyViolation.All";
"233e0cf1-dd62-48bc-b65b-b38fe87fcf8e" = "ChannelSettings.Read.All";
"c97b873f-f59f-49aa-8a0e-52b32d762124" = "ChannelSettings.Read.All";
"d649fb7c-72b4-4eec-b2b4-b15acf79e378" = "ChannelSettings.ReadWrite.All";
"243cded2-bd16-4fd6-a953-ff8177894c3d" = "ChannelSettings.ReadWrite.All";
"38826093-1258-4dea-98f0-00003be2b8d0" = "Chat.Create";
"d9c48af6-9ad9-47ad-82c3-63757137b9af" = "Chat.Create";
"f501c180-9344-439a-bca0-6cbf209fd270" = "Chat.Read";
"6b7d71aa-70aa-4810-a8d9-5d9fb2830017" = "Chat.Read.All";
"1c1b4c8e-3cc7-4c58-8470-9b92c9d5848b" = "Chat.Read.WhereInstalled";
"9547fcb5-d03f-419d-9948-5928bbf71b0f" = "Chat.ReadBasic";
"b2e060da-3baf-4687-9611-f4ebc0f0cbde" = "Chat.ReadBasic.All";
"818ba5bd-5b3e-4fe0-bbe6-aa4686669073" = "Chat.ReadBasic.WhereInstalled";
"9ff7295e-131b-4d94-90e1-69fde507ac11" = "Chat.ReadWrite";
"294ce7c9-31ba-490a-ad7d-97a7d075e4ed" = "Chat.ReadWrite.All";
"ad73ce80-f3cd-40ce-b325-df12c33df713" = "Chat.ReadWrite.WhereInstalled";
"7e847308-e030-4183-9899-5235d7270f58" = "Chat.UpdatePolicyViolation.All";
"c5a9e2b1-faf6-41d4-8875-d381aa549b24" = "ChatMember.Read";
"a3410be2-8e48-4f32-8454-c29a7465209d" = "ChatMember.Read.All";
"93e7c9e4-54c5-4a41-b796-f2a5adaacda7" = "ChatMember.Read.WhereInstalled";
"dea13482-7ea6-488f-8b98-eb5bbecf033d" = "ChatMember.ReadWrite";
"57257249-34ce-4810-a8a2-a03adf0c5693" = "ChatMember.ReadWrite.All";
"e32c2cd9-0124-4e44-88fc-772cd98afbdb" = "ChatMember.ReadWrite.WhereInstalled";
"cdcdac3a-fd45-410d-83ef-554db620e5c7" = "ChatMessage.Read";
"b9bb2381-47a4-46cd-aafb-00cb12f68504" = "ChatMessage.Read.All";
"116b7235-7cc6-461e-b163-8e55691d839e" = "ChatMessage.Send";
"5252ec4e-fd40-4d92-8c68-89dd1d3c6110" = "CloudPC.Read.All";
"a9e09520-8ed4-4cde-838e-4fdea192c227" = "CloudPC.Read.All";
"9d77138f-f0e2-47ba-ab33-cd246c8b79d1" = "CloudPC. ReadWrite. All";
"3b4349e1-8cf5-45a3-95b7-69d1751d3e6a" = "CloudPC. ReadWrite. All";
"f3bfad56-966e-4590-a536-82ecf548ac1e" = "ConsentRequest.Read.All";
"1260ad83-98fb-4785-abbb-d6cc1806fd41" = "ConsentRequest.Read.All";
"497d9dfa-3bd1-481a-baab-90895e54568c" = "ConsentRequest.ReadWrite.all";
"9f1b81a7-0223-4428-bfa4-0bcb5535f27d" = "ConsentRequest.ReadWrite.all";
"ff74d97f-43af-4b68-9f2a-b77ee6968c5d" = "Contacts.Read";
"089fe4d0-434a-44c5-8827-41ba8a0b17f5" = "Contacts.Read";
"242b9d9e-ed24-4d09-9a52-f43769beb9d4" = "Contacts.Read.Shared";
"d56682ec-c09e-4743-aaf4-1a3aac4caa21" = "Contacts.ReadWrite";
"6918b873-d17a-4dc1-b314-35f528134491" = "Contacts.ReadWrite";
"afb6c84b-06be-49af-80bb-8f3f77004eab" = "Contacts.ReadWrite.Shared";
"81594d25-e88e-49cf-ac8c-fecbff49f994" = "CrossTenantInformation.ReadBasic.All";
"cac88765-0581-4025-9725-5ebc13f729ee" = "CrossTenantInformation.ReadBasic.All";
"cb1ba48f-d22b-4325-a07f-74135a62ee41" = "CrossTenantUserProfileSharing.Read";
"759dcd16-3c90-463c-937e-abf89f991c18" = "CrossTenantUserProfileSharing.Read.All";
"8b919d44-6192-4f3d-8a3b-f86f8069ae3c" = "CrossTenantUserProfileSharing.Read.All";
"eed0129d-dc60-4f30-8641-daf337a39ffd" = "CrossTenantUserProfileSharing.ReadWrite";
"64dfa325-cbf8-48e3-938d-51224a0cac01" = "CrossTenantUserProfileSharing.ReadWrite.All";
"306785c5-c09b-4ba0-a4ee-023f3da165cb" = "CrossTenantUserProfileSharing.ReadWrite.All";
"b2052569-c98c-4f36-a5fb-43e5c111e6d0" = "CustomAuthenticationExtension.Read.All";
"88bb2658-5d9e-454f-aacd-a3933e079526" = "CustomAuthenticationExtension.Read.All";
"8dfcf82f-15d0-43b3-bc78-a958a13a5792" = "CustomAuthenticationExtension.ReadWrite.All";
"c2667967-7050-4e7e-b059-4cbbb3811d03" = "CustomAuthenticationExtension.ReadWrite.All";
"214e810f-fda8-4fd7-a475-29461495eb00" = "CustomAuthenticationExtension.Receive.Payload";
"b46ffa80-fe3d-4822-9a1a-c200932d54d0" = "CustomSecAttributeAssignment.Read.All";
"3b37c5a4-1226-493d-bec3-5d6c6b866f3f" = "CustomSecAttributeAssignment.Read.All";
"ca46335e-8453-47cd-a001-8459884efeae" = "CustomSecAttributeAssignment.ReadWrite.All";
"de89b5e4-5b8f-48eb-8925-29c2b33bd8bd" = "CustomSecAttributeAssignment.ReadWrite.All";
"ce026878-a0ff-4745-a728-d4fedd086c07" = "CustomSecAttributeDefinition.Read.All";
"b185aa14-d8d2-42c1-a685-0f5596613624" = "CustomSecAttributeDefinition.Read.All";
"8b0160d4-5743-482b-bb27-efc0a485ca4a" = "CustomSecAttributeDefinition.ReadWrite.All";
"12338004-21f4-4896-bf5e-b75dfaf1016d" = "CustomSecAttributeDefinition.ReadWrite.All";
"0c0064ea-477b-4130-82a5-4c2cc4ff68aa" = "DelegatedAdminRelationship.Read.All";
"f6e9e124-4586-492f-adc0-c6f96e4823fd" = "DelegatedAdminRelationship.Read.All";
"885f682f-a990-4bad-a642-36736a74b0c7" = "DelegatedAdminRelationship.ReadWrite.All";
"cc13eba4-8cd8-44c6-b4d4-f93237adce58" = "DelegatedAdminRelationship.ReadWrite.All";
"41ce6ca6-6826-4807-84f1-1c82854f7ee5" = "DelegatedPermissionGrant.ReadWrite.All";
"8e8e4742-1d95-4f68-9d56-6ee75648c72a" = "DelegatedPermissionGrant.ReadWrite.All";
"bac3b9c2-b516-4ef4-bd3b-c2ef73d8d804" = "Device.Command";
"11d4cd79-5ba5-460f-803f-e22c8ab85ccd" = "Device.Read";
"951183d1-1a61-466f-a6d1-1fde911bfd95" = "Device.Read.All";
"7438b122-aefc-4978-80ed-43db9fcc7715" = "Device.Read.All";
"1138cb37-bd11-4084-a2b7-9f71582aeddb" = "Device.ReadWrite.All";
"280b3b69-0437-44b1-bc20-3b2fca1ee3e9" = "DeviceLocalCredential.Read.All";
"884b599e-4d48-43a5-ba94-15c414d00588" = "DeviceLocalCredential.Read.All";
"9917900e-410b-4d15-846e-42a357488545" = "DeviceLocalCredential.ReadBasic.All";
"db51be59-e728-414b-b800-e0f010df1a79" = "DeviceLocalCredential.ReadBasic.All";
"4edf5f54-4666-44af-9de9-0144fb4b6e8c" = "DeviceManagementApps.Read.All";
"7a6ee1e7-141e-4cec-ae74-d9db155731ff" = "DeviceManagementApps.Read.All";
"7b3f05d5-f68c-4b8d-8c59-a2ecd12f24af" = "DeviceManagementApps.ReadWrite.All";
"78145de6-330d-4800-a6ce-494ff2d33d07" = "DeviceManagementApps.ReadWrite.All";
"f1493658-876a-4c87-8fa7-edb559b3476a" = "DeviceManagementConfiguration.Read.All";
"dc377aa6-52d8-4e23-b271-2a7ae04cedf3" = "DeviceManagementConfiguration.Read.All";
"0883f392-0a7a-443d-8c76-16a6d39c7b63" = "DeviceManagementConfiguration.ReadWrite.All";
"9241abd9-d0e6-425a-bd4f-47ba86e767a4" = "DeviceManagementConfiguration.ReadWrite.All";
"3404d2bf-2b13-457e-a330-c24615765193" = "DeviceManagementManagedDevices.PrivilegedOperations.All";
"5b07b0dd-2377-4e44-a38d-703f09a0dc3c" = "DeviceManagementManagedDevices.PrivilegedOperations.All";
"314874da-47d6-4978-88dc-cf0d37f0bb82" = "DeviceManagementManagedDevices.Read.All";
"2f51be20-0bb4-4fed-bf7b-db946066c75e" = "DeviceManagementManagedDevices.Read.All";
"44642bfe-8385-4adc-8fc6-fe3cb2c375c3" = "DeviceManagementManagedDevices.ReadWrite.All";
"243333ab-4d21-40cb-a475-36241daa0842" = "DeviceManagementManagedDevices.ReadWrite.All";
"49f0cc30-024c-4dfd-ab3e-82e137ee5431" = "DeviceManagementRBAC.Read.All";
"58ca0d9a-1575-47e1-a3cb-007ef2e4583b" = "DeviceManagementRBAC.Read.All";
"0c5e8a55-87a6-4556-93ab-adc52c4d862d" = "DeviceManagementRBAC.ReadWrite.All";
"e330c4f0-4170-414e-a55a-2f022ec2b57b" = "DeviceManagementRBAC.ReadWrite.All";
"8696daa5-bce5-4b2e-83f9-51b6defc4e1e" = "DeviceManagementServiceConfig.Read.All";
"06a5fe6d-c49d-46a7-b082-56b1b14103c7" = "DeviceManagementServiceConfig.Read.All";
"662ed50a-ac44-4eef-ad86-62eed9be2a29" = "DeviceManagementServiceConfig.ReadWrite.All";
"5ac13192-7ace-4fcf-b828-1a26f28068ee" = "DeviceManagementServiceConfig.ReadWrite.All";
"c3ba73cd-1333-4ac0-9eb6-da00cf298dad" = "DigitalHealthSettings.Read";
"0e263e50-5827-48a4-b97c-d940288653c7" = "Directory.AccessAsUser.All";
"06da0dbc-49e2-44d2-8312-53f166ab848a" = "Directory.Read.All";
"7ab1d382-f21e-4acd-a863-ba3e13f7da61" = "Directory.Read.All";
"c5366453-9fb0-48a5-a156-24f0c49a4b84" = "Directory.ReadWrite.All";
"19dbc75e-c2e2-444c-a770-ec69d8559fc7" = "Directory.ReadWrite.All";
"cba5390f-ed6a-4b7f-b657-0efc2210ed20" = "Directory.Write.Restricted";
"f20584af-9290-4153-9280-ff8bb2c0ea7f" = "Directory.Write.Restricted";
"34d3bd24-f6a6-468c-b67c-0c365c1d6410" = "DirectoryRecommendations.Read.All";
"ae73097b-cb2a-4447-b064-5d80f6093921" = "DirectoryRecommendations.Read.All";
"f37235e8-90a0-4189-93e2-e55b53867ccd" = "DirectoryRecommendations.ReadWrite.All";
"0e9eea12-4f01-45f6-9b8d-3ea4c8144158" = "DirectoryRecommendations.ReadWrite.All";
"2f9ee017-59c1-4f1d-9472-bd5529a7b311" = "Domain.Read.All";
"dbb9058a-0e50-45d7-ae91-66909b5d4664" = "Domain.Read.All";
"0b5d694c-a244-4bde-86e6-eb5cd07730fe" = "Domain.ReadWrite.All";
"7e05723c-0bb0-42da-be95-ae9f08a6e53c" = "Domain.ReadWrite.All";
"ff91d191-45a0-43fd-b837-bd682c4a0b0f" = "EAS.AccessAsUser.All";
"99201db3-7652-4d5a-809a-bdb94f85fe3c" = "eDiscovery.Read.All";
"50180013-6191-4d1e-a373-e590ff4e66af" = "eDiscovery.Read.All";
"acb8f680-0834-4146-b69e-4ab1b39745ad" = "eDiscovery.ReadWrite.All";
"b2620db1-3bf7-4c5b-9cb9-576d29eac736" = "eDiscovery.ReadWrite.All";
"8523895c-6081-45bf-8a5d-f062a2f12c9f" = "EduAdministration.Read";
"7c9db06a-ec2d-4e7b-a592-5a1e30992566" = "EduAdministration.Read.All";
"63589852-04e3-46b4-bae9-15d5b1050748" = "EduAdministration.ReadWrite";
"9bc431c3-b8bc-4a8d-a219-40f10f92eff6" = "EduAdministration.ReadWrite.All";
"091460c9-9c4a-49b2-81ef-1f3d852acce2" = "EduAssignments.Read";
"4c37e1b6-35a1-43bf-926a-6f30f2cdf585" = "EduAssignments.Read.All";
"c0b0103b-c053-4b2e-9973-9f3a544ec9b8" = "EduAssignments.ReadBasic";
"6e0a958b-b7fc-4348-b7c4-a6ab9fd3dd0e" = "EduAssignments.ReadBasic.All";
"2f233e90-164b-4501-8bce-31af2559a2d3" = "EduAssignments.ReadWrite";
"0d22204b-6cad-4dd0-8362-3e3f2ae699d9" = "EduAssignments.ReadWrite.All";
"2ef770a1-622a-47c4-93ee-28d6adbed3a0" = "EduAssignments.ReadWriteBasic";
"f431cc63-a2de-48c4-8054-a34bc093af84" = "EduAssignments.ReadWriteBasic.All";
"a4389601-22d9-4096-ac18-36a927199112" = "EduRoster.Read";
"e0ac9e1b-cb65-4fc5-87c5-1a8bc181f648" = "EduRoster.Read.All";
"5d186531-d1bf-4f07-8cea-7c42119e1bd9" = "EduRoster.ReadBasic";
"0d412a8c-a06c-439f-b3ec-8abcf54d2f96" = "EduRoster.ReadBasic.All";
"359e19a6-e3fa-4d7f-bcab-d28ec592b51e" = "EduRoster.ReadWrite";
"d1808e82-ce13-47af-ae0d-f9b254e6d58a" = "EduRoster.ReadWrite.All";
"64a6cdd6-aab1-4aaf-94b8-3cc8405e90d0" = "correo electrónico";
"5449aa12-1393-4ea2-a7c7-d0e06c1a56b2" = "EntitlementManagement.Read.All";
"c74fd47d-ed3c-45c3-9a9e-b8676de685d2" = "EntitlementManagement.Read.All";
"ae7a573d-81d7-432b-ad44-4ed5c9d89038" = "EntitlementManagement.ReadWrite.All";
"9acd699f-1e81-4958-b001-93b1d2506e19" = "EntitlementManagement.ReadWrite.All";
"e9fdcbbb-8807-410f-b9ec-8d5468c7c2ac" = "EntitlementMgmt-SubjectAccess.ReadWrite";
"f7dd3bed-5eec-48da-bc73-1c0ef50bc9a1" = "EventListener.Read.All";
"b7f6385c-6ce6-4639-a480-e23c42ed9784" = "EventListener.Read.All";
"d11625a6-fe21-4fc6-8d3d-063eba5525ad" = "EventListener.ReadWrite.All";
"0edf5e9e-4ce8-468a-8432-d08631d18c43" = "EventListener.ReadWrite.All";
"9769c687-087d-48ac-9cb3-c37dde652038" = "EWS.AccessAsUser.All";
"a38267a5-26b6-4d76-9493-935b7599116b" = "ExternalConnection.Read.All";
"1914711b-a1cb-4793-b019-c2ce0ed21b8c" = "ExternalConnection.Read.All";
"bbbbd9b3-3566-4931-ac37-2b2180d9e334" = "ExternalConnection.ReadWrite.All";
"34c37bc0-2b40-4d5e-85e1-2365cd256d79" = "ExternalConnection.ReadWrite.All";
"4082ad95-c812-4f02-be92-780c4c4f1830" = "ExternalConnection.ReadWrite.OwnedBy";
"f431331c-49a6-499f-be1c-62af19c34a9d" = "ExternalConnection.ReadWrite.OwnedBy";
"922f9392-b1b7-483c-a4be-0089be7704fb" = "ExternalItem.Read.All";
"7a7cffad-37d2-4f48-afa4-c6ab129adcc2" = "ExternalItem.Read.All";
"b02c54f8-eb48-4c50-a9f0-a149e5a2012f" = "ExternalItem.ReadWrite.All";
"38c3d6ee-69ee-422f-b954-e17819665354" = "ExternalItem.ReadWrite.All";
"4367b9d7-cee7-4995-853c-a0bdfe95c1f9" = "ExternalItem.ReadWrite.OwnedBy";
"8116ae0f-55c2-452d-9944-d18420f5b2c8" = "ExternalItem.ReadWrite.OwnedBy";
"3a1e4806-a744-4c70-80fc-223bf8582c46" = "Family.Read";
"10465720-29dd-4523-a11a-6a75c743c9d9" = "Files.Read";
"df85f4d6-205c-4ac5-a5ea-6bf408dba283" = "Files.Read.All";
"01d4889c-1287-42c6-ac1f-5d1e02578ef6" = "Files.Read.All";
"5447fe39-cb82-4c1a-b977-520e67e724eb" = "Files.Read.Selected";
"5c28f0bf-8a70-41f1-8ab2-9032436ddb65" = "Files.ReadWrite";
"863451e7-0667-486c-a5d6-d135439485f0" = "Files.ReadWrite.All";
"75359482-378d-4052-8f01-80520e7db3cd" = "Files.ReadWrite.All";
"8019c312-3263-48e6-825e-2b833497195b" = "Files.ReadWrite.AppFolder";
"17dde5bd-8c17-420f-a486-969730c1b827" = "Files.ReadWrite.Selected";
"f534bf13-55d4-45a9-8f3c-c92fe64d6131" = "Financials.ReadWrite.All";
"bf7b1a76-6e77-406b-b258-bf5c7720e98f" = "Group.Create";
"5f8c59db-677d-491f-a6b8-5f174b11ec1d" = "Group.Read.All";
"5b567255-7703-4780-807c-7be8301ae99b" = "Group.Read.All";
"4e46008b-f24c-477d-8fff-7bb4ec7aafe0" = "Group.ReadWrite.All";
"62a82d76-70ea-41e2-9197-370581804d09" = "Group.ReadWrite.All";
"bc024368-1153-4739-b217-4326f2e966d0" = "GroupMember.Read.All";
"98830695-27a2-44f7-8c18-0c3ebc9698f6" = "GroupMember.Read.All";
"f81125ac-d3b7-4573-a3b2-7099cc39df9e" = "GroupMember.ReadWrite.All";
"dbaae8cf-10b5-4b86-a4a1-f871c94c6695" = "GroupMember.ReadWrite.All";
"43781733-b5a7-4d1b-98f4-e8edff23e1a9" = "IdentityProvider.Read.All";
"e321f0bb-e7f7-481e-bb28-e3b0b32d4bd0" = "IdentityProvider.Read.All";
"f13ce604-1677-429f-90bd-8a10b9f01325" = "IdentityProvider.ReadWrite.All";
"90db2b9a-d928-4d33-a4dd-8442ae3d41e4" = "IdentityProvider.ReadWrite.All";
"8f6a01e7-0391-4ee5-aa22-a3af122cef27" = "IdentityRiskEvent.Read.All";
"6e472fd1-ad78-48da-a0f0-97ab2c6b769e" = "IdentityRiskEvent.Read.All";
"9e4862a5-b68f-479e-848a-4e07e25c9916" = "IdentityRiskEvent.ReadWrite.All";
"db06fb33-1953-4b7b-a2ac-f1e2c854f7ae" = "IdentityRiskEvent.ReadWrite.All";
"ea5c4ab0-5a73-4f35-8272-5d5337884e5d" = "IdentityRiskyServicePrincipal.Read.All";
"607c7344-0eed-41e5-823a-9695ebe1b7b0" = "IdentityRiskyServicePrincipal.Read.All";
"bb6f654c-d7fd-4ae3-85c3-fc380934f515" = "IdentityRiskyServicePrincipal.ReadWrite.All";
"cb8d6980-6bcb-4507-afec-ed6de3a2d798" = "IdentityRiskyServicePrincipal.ReadWrite.All";
"d04bb851-cb7c-4146-97c7-ca3e71baf56c" = "IdentityRiskyUser.Read.All";
"dc5007c0-2d7d-4c42-879c-2dab87571379" = "IdentityRiskyUser.Read.All";
"e0a7cdbb-08b0-4697-8264-0069786e9674" = "IdentityRiskyUser.ReadWrite.All";
"656f6061-f9fe-4807-9708-6a2e0934df76" = "IdentityRiskyUser.ReadWrite.All";
"2903d63d-4611-4d43-99ce-a33f3f52e343" = "IdentityUserFlow.Read.All";
"1b0c317f-dd31-4305-9932-259a8b6e8099" = "IdentityUserFlow.Read.All";
"281892cc-4dbf-4e3a-b6cc-b21029bb4e82" = "IdentityUserFlow.ReadWrite.All";
"65319a09-a2be-469d-8782-f6b07debf789" = "IdentityUserFlow.ReadWrite.All";
"652390e4-393a-48de-9484-05f9b1212954" = "IMAP.AccessAsUser.All";
"60382b96-1f5e-46ea-a544-0407e489e588" = "IndustryData.ReadBasic.All";
"4f5ac95f-62fd-472c-b60f-125d24ca0bc5" = "IndustryData.ReadBasic.All";
"d19c0de5-7ecb-4aba-b090-da35ebcd5425" = "IndustryData-DataConnector.Read.All";
"7ab52c2f-a2ee-4d98-9ebc-725e3934aae2" = "IndustryData-DataConnector.Read.All";
"5ce933ac-3997-4280-aed0-cc072e5c062a" = "IndustryData-DataConnector.ReadWrite.All";
"eda0971c-482e-4345-b28f-69c309cb8a34" = "IndustryData-DataConnector.ReadWrite.All";
"fc47391d-ab2c-410f-9059-5600f7af660d" = "IndustryData-DataConnector.Upload";
"9334c44b-a7c6-4350-8036-6bf8e02b4c1f" = "IndustryData-DataConnector.Upload";
"cb0774da-a605-42af-959c-32f438fb38f4" = "IndustryData-InboundFlow.Read.All";
"305f6ba2-049a-4b1b-88bb-fe7e08758a00" = "IndustryData-InboundFlow.Read.All";
"97044676-2cec-40ee-bd70-38df444c9e70" = "IndustryData-InboundFlow.ReadWrite.All";
"e688c61f-d4c6-4d64-a197-3bcf6ba1d6ad" = "IndustryData-InboundFlow.ReadWrite.All";
"a3f96ffe-cb84-40a8-ac85-582d7ef97c2a" = "IndustryData-ReferenceDefinition.Read.All";
"6ee891c3-74a4-4148-8463-0c834375dfaf" = "IndustryData-ReferenceDefinition.Read.All";
"92685235-50c4-4702-b2c8-36043db6fa79" = "IndustryData-Run.Read.All";
"f6f5d10b-3024-4d1d-b674-aae4df4a1a73" = "IndustryData-Run.Read.All";
"49b7016c-89ae-41e7-bd6f-b7170c5490bf" = "IndustryData-SourceSystem.Read.All";
"bc167a60-39fe-4865-8b44-78400fc6ed03" = "IndustryData-SourceSystem.Read.All";
"9599f005-05d6-4ea7-b1b1-4929768af5d0" = "IndustryData-SourceSystem.ReadWrite.All";
"7d866958-e06e-4dd6-91c6-a086b3f5cfeb" = "IndustryData-SourceSystem.ReadWrite.All";
"c9d51f28-8ccd-42b2-a836-fd8fe9ebf2ae" = "IndustryData-TimePeriod.Read.All";
"7c55c952-b095-4c23-a522-022bce4cc1e3" = "IndustryData-TimePeriod.Read.All";
"b6d56528-3032-4f9d-830f-5a24a25e6661" = "IndustryData-TimePeriod.ReadWrite.All";
"7afa7744-a782-4a32-b8c2-e3db637e8de7" = "IndustryData-TimePeriod.ReadWrite.All";
"cbe6c7e4-09aa-4b8d-b3c3-2dbb59af4b54" = "InformationProtectionContent.Sign.All";
"287bd98c-e865-4e8c-bade-1a85523195b9" = "InformationProtectionContent.Write.All";
"4ad84827-5578-4e18-ad7a-86530b12f884" = "InformationProtectionPolicy.Read";
"19da66cb-0fb0-4390-b071-ebc76a349482" = "InformationProtectionPolicy.Read.All";
"ea4c1fd9-6a9f-4432-8e5d-86e06cc0da77" = "LearningContent.Read.All";
"8740813e-d8aa-4204-860e-2a0f8f84dbc8" = "LearningContent.Read.All";
"53cec1c4-a65f-4981-9dc1-ad75dbf1c077" = "LearningContent.ReadWrite.All";
"444d6fcb-b738-41e5-b103-ac4f2a2628a3" = "LearningContent.ReadWrite.All";
"dd8ce36f-9245-45ea-a99e-8ac398c22861" = "LearningProvider.Read";
"40c2eb57-abaf-49f5-9331-e90fd01f7130" = "LearningProvider.ReadWrite";
"f55016cc-149c-447e-8f21-7cf3ec1d6350" = "LicenseAssignment.ReadWrite.All";
"5facf0c1-8979-4e95-abcf-ff3d079771c0" = "LicenseAssignment.ReadWrite.All";
"9bcb9916-765a-42af-bf77-02282e26b01a" = "LifecycleWorkflows.Read.All";
"7c67316a-232a-4b84-be22-cea2c0906404" = "LifecycleWorkflows.Read.All";
"84b9d731-7db8-4454-8c90-fd9e95350179" = "LifecycleWorkflows.ReadWrite.All";
"5c505cf4-8424-4b8e-aa14-ee06e3bb23e3" = "LifecycleWorkflows.ReadWrite.All";
"570282fd-fa5c-430d-a7fd-fc8dc98a9dca" = "Mail.Read";
"810c84a8-4a9e-49e6-bf7d-12d183f40d01" = "Mail.Read";
"7b9103a5-4610-446b-9670-80643382c1fa" = "Mail.Read.Shared";
"a4b8392a-d8d1-4954-a029-8e668a39a170" = "Mail.ReadBasic";
"6be147d2-ea4f-4b5a-a3fa-3eab6f3c140a" = "Mail.ReadBasic";
"693c5e45-0940-467d-9b8a-1022fb9d42ef" = "Mail.ReadBasic.All";
"b11fa0e7-fdb7-4dc9-b1f1-59facd463480" = "Mail.ReadBasic.Shared";
"024d486e-b451-40bb-833d-3e66d98c5c73" = "Mail.ReadWrite";
"e2a3a72e-5f79-4c64-b1b1-878b674786c9" = "Mail.ReadWrite";
"5df07973-7d5d-46ed-9847-1271055cbd51" = "Mail.ReadWrite.Shared";
"e383f46e-2787-4529-855e-0e479a3ffac0" = "Mail.Send";
"b633e1c5-b582-4048-a93e-9f11b44c7e96" = "Mail.Send";
"a367ab51-6b49-43bf-a716-a1fb06d2a174" = "Mail.Send.Shared";
"87f447af-9fa4-4c32-9dfa-4a57a73d18ce" = "MailboxSettings.Read";
"40f97065-369a-49f4-947c-6a255697ae91" = "MailboxSettings.Read";
"818c620a-27a9-40bd-a6a5-d96f7d610b4b" = "MailboxSettings.ReadWrite";
"6931bccd-447a-43d1-b442-00a195474933" = "MailboxSettings.ReadWrite";
"dc34164e-6c4a-41a0-be89-3ae2fbad7cd3" = "ManagedTenants.Read.All";
"b31fa710-c9b3-4d9e-8f5e-8036eecddab9" = "ManagedTenants.ReadWrite.All";
"f6a3db3e-f7e8-4ed2-a414-557c8c9830be" = "Member.Read.Hidden";
"658aa5d8-239f-45c4-aa12-864f4fc7e490" = "Member.Read.Hidden";
"4051c7fc-b429-4804-8d80-8f1f8c24a6f7" = "NetworkAccessBranch.Read.All";
"39ae4a24-1ef0-49e8-9d63-2a66f5c39edd" = "NetworkAccessBranch.Read.All";
"b8a36cc2-b810-461a-baa4-a7281e50bd5c" = "NetworkAccessBranch.ReadWrite.All";
"8137102d-ec16-4191-aaf8-7aeda8026183" = "NetworkAccessBranch.ReadWrite.All";
"ba22922b-752c-446f-89d7-a2d92398fceb" = "NetworkAccessPolicy.Read.All";
"8a3d36bf-cb46-4bcc-bec9-8d92829dab84" = "NetworkAccessPolicy.Read.All";
"b1fbad0f-ef6e-42ed-8676-bca7fa3e7291" = "NetworkAccessPolicy.ReadWrite.All";
"f0c341be-8348-4989-8e43-660324294538" = "NetworkAccessPolicy.ReadWrite.All";
"9d822255-d64d-4b7a-afdb-833b9a97ed02" = "Notes.Create";
"371361e4-b9e2-4a3f-8315-2a301a3b0a3d" = "Notes.Read";
"dfabfca6-ee36-4db2-8208-7a28381419b3" = "Notes.Read.All";
"3aeca27b-ee3a-4c2b-8ded-80376e2134a4" = "Notes.Read.All";
"615e26af-c38a-4150-ae3e-c3b0d4cb1d6a" = "Notes.ReadWrite";
"64ac0503-b4fa-45d9-b544-71a463f05da0" = "Notes.ReadWrite.All";
"0c458cef-11f3-48c2-a568-c66751c238c0" = "Notes.ReadWrite.All";
"ed68249d-017c-4df5-9113-e684c7f8760b" = "Notes.ReadWrite.CreatedByApp";
"89497502-6e42-46a2-8cb2-427fd3df970a" = "Notifications.ReadWrite.CreatedByApp";
"7427e0e9-2fba-42fe-b0c0-848c9e6a8182" = "offline_access";
"110e5abb-a10c-4b59-8b55-9b4daa4ef743" = "OnlineMeetingArtifact.Read.All";
"df01ed3b-eb61-4eca-9965-6b3d789751b2" = "OnlineMeetingArtifact.Read.All";
"190c2bb6-1fdd-4fec-9aa2-7d571b5e1fe3" = "OnlineMeetingRecording.Read.All";
"a4a08342-c95d-476b-b943-97e100569c8d" = "OnlineMeetingRecording.Read.All";
"9be106e1-f4e3-4df5-bdff-e4bc531cbe43" = "OnlineMeetings.Read";
"c1684f21-1984-47fa-9d61-2dc8c296bb70" = "OnlineMeetings.Read.All";
"a65f2972-a4f8-4f5e-afd7-69ccb046d5dc" = "OnlineMeetings.ReadWrite";
"b8bb2037-6e08-44ac-a4ea-4674e010e2a4" = "OnlineMeetings.ReadWrite.All";
"30b87d18-ebb1-45db-97f8-82ccb1f0190c" = "OnlineMeetingTranscript.Read.All";
"a4a80d8d-d283-4bd8-8504-555ec3870630" = "OnlineMeetingTranscript.Read.All";
"f6609722-4100-44eb-b747-e6ca0536989d" = "OnPremDirectorySynchronization.Read.All";
"c2d95988-7604-4ba1-aaed-38a5f82a51c7" = "OnPremDirectorySynchronization.ReadWrite.All";
"8c4d5184-71c2-4bf8-bb9d-bc3378c9ad42" = "OnPremisesPublishingProfiles.ReadWrite.All";
"0b57845e-aa49-4e6f-8109-ce654fffa618" = "OnPremisesPublishingProfiles.ReadWrite.All";
"37f7f235-527c-4136-accd-4a02d197296e" = "OpenID";
"4908d5b9-3fb2-4b1e-9336-1888b7937185" = "Organization.Read.All";
"498476ce-e0fe-48b0-b801-37ba7e2685c6" = "Organization.Read.All";
"46ca0847-7e6b-426e-9775-ea810a948356" = "Organization.ReadWrite.All";
"292d869f-3427-49a8-9dab-8c70152b74e9" = "Organization.ReadWrite.All";
"08432d1b-5911-483c-86df-7980af5cdee0" = "OrgContact.Read.All";
"e1a88a34-94c4-4418-be12-c87b00e26bea" = "OrgContact.Read.All";
"ba47897c-39ec-4d83-8086-ee8256fa737d" = "People.Read";
"b89f9189-71a5-4e70-b041-9887f0bc7e4a" = "People.Read.All";
"b528084d-ad10-4598-8b93-929746b4d7d6" = "People.Read.All";
"cb8f45a0-5c2e-4ea1-b803-84b870a7d7ec" = "Place.Read.All";
"913b9306-0ce1-42b8-9137-6a7df690a760" = "Place.Read.All";
"4c06a06a-098a-4063-868e-5dfee3827264" = "Place.ReadWrite.All";
"572fea84-0151-49b2-9301-11cb16974376" = "Policy.Read.All";
"246dd0d5-5bd0-4def-940b-0421030a5b68" = "Policy.Read.All";
"633e0fce-8c58-4cfb-9495-12bbd5a24f7c" = "Policy.Read.ConditionalAccess";
"37730810-e9ba-4e46-b07e-8ca78d182097" = "Policy.Read.ConditionalAccess";
"414de6ea-2d92-462f-b120-6e2a809a6d01" = "Policy.Read.PermissionGrant";
"9e640839-a198-48fb-8b9a-013fd6f6cbcd" = "Policy.Read.PermissionGrant";
"4f5bc9c8-ea54-4772-973a-9ca119cb0409" = "Policy.ReadWrite.AccessReview";
"77c863fd-06c0-47ce-a7eb-49773e89d319" = "Policy.ReadWrite.AccessReview";
"b27add92-efb2-4f16-84f5-8108ba77985c" = "Policy.ReadWrite.ApplicationConfiguration";
"be74164b-cff1-491c-8741-e671cb536e13" = "Policy.ReadWrite.ApplicationConfiguration";
"edb72de9-4252-4d03-a925-451deef99db7" = "Policy.ReadWrite.AuthenticationFlows";
"25f85f3c-f66c-4205-8cd5-de92dd7f0cec" = "Policy.ReadWrite.AuthenticationFlows";
"7e823077-d88e-468f-a337-e18f1f0e6c7c" = "Policy.ReadWrite.AuthenticationMethod";
"29c18626-4985-4dcd-85c0-193eef327366" = "Policy.ReadWrite.AuthenticationMethod";
"edd3c878-b384-41fd-95ad-e7407dd775be" = "Policy.ReadWrite.Authorization";
"fb221be6-99f2-473f-bd32-01c6a0e9ca3b" = "Policy.ReadWrite.Authorization";
"ad902697-1014-4ef5-81ef-2b4301988e8c" = "Policy.ReadWrite.ConditionalAccess";
"01c0a623-fc9b-48e9-b794-0756f8e8f067" = "Policy.ReadWrite.ConditionalAccess";
"4d135e65-66b8-41a8-9f8b-081452c91774" = "Policy.ReadWrite.ConsentRequest";
"999f8c63-0a38-4f1b-91fd-ed1947bdd1a9" = "Policy.ReadWrite.ConsentRequest";
"014b43d0-6ed4-4fc6-84dc-4b6f7bae7d85" = "Policy.ReadWrite.CrossTenantAccess";
"338163d7-f101-4c92-94ba-ca46fe52447c" = "Policy.ReadWrite.CrossTenantAccess";
"40b534c3-9552-4550-901b-23879c90bcf9" = "Policy.ReadWrite.DeviceConfiguration";
"b5219784-1215-45b5-b3f1-88fe1081f9c0" = "Policy.ReadWrite.ExternalIdentities";
"03cc4f92-788e-4ede-b93f-199424d144a5" = "Policy.ReadWrite.ExternalIdentities";
"92a38652-f13b-4875-bc77-6e1dbb63e1b2" = "Policy.ReadWrite.FeatureRollout";
"2044e4f1-e56c-435b-925c-44cd8f6ba89a" = "Policy.ReadWrite.FeatureRollout";
"a8ead177-1889-4546-9387-f25e658e2a79" = "Policy.ReadWrite.MobilityManagement";
"2672f8bb-fd5e-42e0-85e1-ec764dd2614e" = "Policy.ReadWrite.PermissionGrant";
"a402ca1c-2696-4531-972d-6e5ee4aa11ea" = "Policy.ReadWrite.PermissionGrant";
"0b2a744c-2abf-4f1e-ad7e-17a087e2be99" = "Policy.ReadWrite.SecurityDefaults";
"1c6e93a6-28e2-4cbb-9f64-1a46a821124d" = "Policy.ReadWrite.SecurityDefaults";
"cefba324-1a70-4a6e-9c1d-fd670b7ae392" = "Policy.ReadWrite.TrustFramework";
"79a677f7-b79d-40d0-a36a-3e6f8688dd7a" = "Policy.ReadWrite.TrustFramework";
"d7b7f2d9-0f45-4ea1-9d42-e50810c06991" = "POP.AccessAsUser.All";
"76bc735e-aecd-4a1d-8b4c-2b915deabb79" = "Presence.Read";
"9c7a330d-35b3-4aa1-963d-cb2b9f927841" = "Presence.Read.All";
"8d3c54a7-cf58-4773-bf81-c0cd6ad522bb" = "Presence.ReadWrite";
"83cded22-8297-4ff6-a7fa-e97e9545a259" = "Presence.ReadWrite.All";
"d69c2d6d-4f72-4f99-a6b9-663e32f8cf68" = "PrintConnector.Read.All";
"79ef9967-7d59-4213-9c64-4b10687637d8" = "PrintConnector.ReadWrite.All";
"90c30bed-6fd1-4279-bf39-714069619721" = "Printer.Create";
"93dae4bd-43a1-4a23-9a1a-92957e1d9121" = "Printer.FullControl.All";
"3a736c8a-018e-460a-b60c-863b2683e8bf" = "Printer.Read.All";
"9709bb33-4549-49d4-8ed9-a8f65e45bb0f" = "Printer.Read.All";
"89f66824-725f-4b8f-928e-e1c5258dc565" = "Printer.ReadWrite.All";
"f5b3f73d-6247-44df-a74c-866173fddab0" = "Printer.ReadWrite.All";
"ed11134d-2f3f-440d-a2e1-411efada2502" = "PrinterShare.Read.All";
"5fa075e9-b951-4165-947b-c63396ff0a37" = "PrinterShare.ReadBasic.All";
"06ceea37-85e2-40d7-bec3-91337a46038f" = "PrinterShare.ReadWrite.All";
"21f0d9c0-9f13-48b3-94e0-b6b231c7d320" = "PrintJob.Create";
"58a52f47-9e36-4b17-9ebe-ce4ef7f3e6c8" = "PrintJob.Manage.All";
"248f5528-65c0-4c88-8326-876c7236df5e" = "PrintJob.Read";
"afdd6933-a0d8-40f7-bd1a-b5d778e8624b" = "PrintJob.Read.All";
"ac6f956c-edea-44e4-bd06-64b1b4b9aec9" = "PrintJob.Read.All";
"6a71a747-280f-4670-9ca0-a9cbf882b274" = "PrintJob.ReadBasic";
"04ce8d60-72ce-4867-85cf-6d82f36922f3" = "PrintJob.ReadBasic.All";
"fbf67eee-e074-4ef7-b965-ab5ce1c1f689" = "PrintJob.ReadBasic.All";
"b81dd597-8abb-4b3f-a07a-820b0316ed04" = "PrintJob.ReadWrite";
"036b9544-e8c5-46ef-900a-0646cc42b271" = "PrintJob.ReadWrite.All";
"5114b07b-2898-4de7-a541-53b0004e2e13" = "PrintJob.ReadWrite.All";
"6f2d22f2-1cb6-412c-a17c-3336817eaa82" = "PrintJob.ReadWriteBasic";
"3a0db2f6-0d2a-4c19-971b-49109b19ad3d" = "PrintJob.ReadWriteBasic.All";
"57878358-37f4-4d3a-8c20-4816e0d457b1" = "PrintJob.ReadWriteBasic.All";
"490f32fd-d90f-4dd7-a601-ff6cdc1a3f6c" = "PrintSettings.Read.All";
"b5991872-94cf-4652-9765-29535087c6d8" = "PrintSettings.Read.All";
"9ccc526a-c51c-4e5c-a1fd-74726ef50b8f" = "PrintSettings.ReadWrite.All";
"456b71a7-0ee0-4588-9842-c123fcc8f664" = "PrintTaskDefinition.ReadWrite.All";
"b3a539c9-59cb-4ad5-825a-041ddbdc2bdb" = "PrivilegedAccess.Read.AzureAD";
"4cdc2547-9148-4295-8d11-be0db1391d6b" = "PrivilegedAccess.Read.AzureAD";
"d329c81c-20ad-4772-abf9-3f6fdb7e5988" = "PrivilegedAccess.Read.AzureADGroup";
"01e37dc9-c035-40bd-b438-b2879c4870a6" = "PrivilegedAccess.Read.AzureADGroup";
"1d89d70c-dcac-4248-b214-903c457af83a" = "PrivilegedAccess.Read.AzureResources";
"5df6fe86-1be0-44eb-b916-7bd443a71236" = "PrivilegedAccess.Read.AzureResources";
"3c3c74f5-cdaa-4a97-b7e0-4e788bfcfb37" = "PrivilegedAccess.ReadWrite.AzureAD";
"854d9ab1-6657-4ec8-be45-823027bcd009" = "PrivilegedAccess.ReadWrite.AzureAD";
"32531c59-1f32-461f-b8df-6f8a3b89f73b" = "PrivilegedAccess.ReadWrite.AzureADGroup";
"2f6817f8-7b12-4f0f-bc18-eeaf60705a9e" = "PrivilegedAccess.ReadWrite.AzureADGroup";
"a84a9652-ffd3-496e-a991-22ba5529156a" = "PrivilegedAccess.ReadWrite.AzureResources";
"6f9d5abc-2db6-400b-a267-7de22a40fb87" = "PrivilegedAccess.ReadWrite.AzureResources";
"14dad69e-099b-42c9-810b-d002981feec1" = "perfil";
"c492a2e1-2f8f-4caa-b076-99bbf6e40fe4" = "ProgramControl.Read.All";
"eedb7fdd-7539-4345-a38b-4839e4a84cbd" = "ProgramControl.Read.All";
"50fd364f-9d93-4ae1-b170-300e87cccf84" = "ProgramControl.ReadWrite.All";
"60a901ed-09f7-4aa5-a16e-7dd3d6f9de36" = "ProgramControl.ReadWrite.All";
"f73fa04f-b9a5-4df9-8843-993ce928925e" = "QnA.Read.All";
"ee49e170-1dd1-4030-b44c-61ad6e98f743" = "QnA.Read.All";
"07f995eb-fc67-4522-ad66-2b8ca8ea3efd" = "RecordsManagement.Read.All";
"ac3a2b8e-03a3-4da9-9ce0-cbe28bf1accd" = "RecordsManagement.Read.All";
"f2833d75-a4e6-40ab-86d4-6dfe73c97605" = "RecordsManagement.ReadWrite.All";
"eb158f57-df43-4751-8b21-b8932adb3d34" = "RecordsManagement.ReadWrite.All";
"02e97553-ed7b-43d0-ab3c-f8bace0d040c" = "Reports.Read.All";
"230c1aed-a721-4c5d-9cb4-a90514e508ef" = "Reports.Read.All";
"84fac5f4-33a9-4100-aa38-a20c6d29e5e7" = "ReportSettings.Read.All";
"ee353f83-55ef-4b78-82da-555bfa2b4b95" = "ReportSettings.Read.All";
"b955410e-7715-4a88-a940-dfd551018df3" = "ReportSettings.ReadWrite.All";
"2a60023f-3219-47ad-baa4-40e17cd02a1d" = "ReportSettings.ReadWrite.All";
"344a729c-0285-42c6-9014-f12b9b8d6129" = "RoleAssignmentSchedule.Read.Directory";
"8c026be3-8e26-4774-9372-8d5d6f21daff" = "RoleAssignmentSchedule.ReadWrite.Directory";
"eb0788c2-6d4e-4658-8c9e-c0fb8053f03d" = "RoleEligibilitySchedule.Read.Directory";
"62ade113-f8e0-4bf9-a6ba-5acb31db32fd" = "RoleEligibilitySchedule.ReadWrite.Directory";
"48fec646-b2ba-4019-8681-8eb31435aded" = "RoleManagement.Read.All";
"c7fbd983-d9aa-4fa7-84b8-17382c103bc4" = "RoleManagement.Read.All";
"9619b88a-8a25-48a7-9571-d23be0337a79" = "RoleManagement.Read.CloudPC";
"031a549a-bb80-49b6-8032-2068448c6a3c" = "RoleManagement.Read.CloudPC";
"741c54c3-0c1e-44a1-818b-3f97ab4e8c83" = "RoleManagement.Read.Directory";
"483bed4a-2ad3-4361-a73b-c83ccdbdc53c" = "RoleManagement.Read.Directory";
"501d06f8-07b8-4f18-b5c6-c191a4af7a82" = "RoleManagement.ReadWrite.CloudPC";
"274d0592-d1b6-44bd-af1d-26d259bcb43a" = "RoleManagement.ReadWrite.CloudPC";
"d01b97e9-cbc0-49fe-810a-750afd5527a3" = "RoleManagement.ReadWrite.Directory";
"9e3f62cf-ca93-4989-b6ce-bf83c28f9fe8" = "RoleManagement.ReadWrite.Directory";
"cce71173-f76d-446e-97ff-efb2d82e11b1" = "RoleManagementAlert.Read.Directory";
"ef31918f-2d50-4755-8943-b8638c0a077e" = "RoleManagementAlert.Read.Directory";
"435644c6-a5b1-40bf-8f52-fe8e5b53e19c" = "RoleManagementAlert.ReadWrite.Directory";
"11059518-d6a6-4851-98ed-509268489c4a" = "RoleManagementAlert.ReadWrite.Directory";
"3de2cdbe-0ff5-47d5-bdee-7f45b4749ead" = "RoleManagementPolicy.Read.Directory";
"1ff1be21-34eb-448c-9ac9-ce1f506b2a68" = "RoleManagementPolicy.ReadWrite.Directory";
"fccf6dd8-5706-49fa-811f-69e2e1b585d0" = "Schedule.Read.All";
"7b2ebf90-d836-437f-b90d-7b62722c4456" = "Schedule.Read.All";
"63f27281-c9d9-4f29-94dd-6942f7f1feb0" = "Schedule.ReadWrite.All";
"b7760610-0545-4e8a-9ec3-cce9e63db01c" = "Schedule.ReadWrite.All";
"7d307522-aa38-4cd0-bd60-90c6f0ac50bd" = "SearchConfiguration.Read.All";
"ada977a5-b8b1-493b-9a91-66c206d76ecf" = "SearchConfiguration.Read.All";
"b1a7d408-cab0-47d2-a2a5-a74a3733600d" = "SearchConfiguration.ReadWrite.All";
"0e778b85-fefa-466d-9eec-750569d92122" = "SearchConfiguration.ReadWrite.All";
"1638cddf-07a4-4de2-8645-69c96cacad73" = "SecurityActions.Read.All";
"5e0edab9-c148-49d0-b423-ac253e121825" = "SecurityActions.Read.All";
"dc38509c-b87d-4da0-bd92-6bec988bac4a" = "SecurityActions.ReadWrite.All";
"f2bf083f-0179-402a-bedb-b2784de8a49b" = "SecurityActions.ReadWrite.All";
"bc257fb8-46b4-4b15-8713-01e91bfbe4ea" = "SecurityAlert.Read.All";
"472e4a4d-bb4a-4026-98d1-0b0d74cb74a5" = "SecurityAlert.Read.All";
"471f2a7f-2a42-4d45-a2bf-594d0838070d" = "SecurityAlert.ReadWrite.All";
"ed4fca05-be46-441f-9803-1873825f8fdb" = "SecurityAlert.ReadWrite.All";
"64733abd-851e-478a-bffb-e47a14b18235" = "SecurityEvents.Read.All";
"bf394140-e372-4bf9-a898-299cfc7564e5" = "SecurityEvents.Read.All";
"6aedf524-7e1c-45a7-bd76-ded8cab8d0fc" = "SecurityEvents.ReadWrite.All";
"d903a879-88e0-4c09-b0c9-82f6a1333f84" = "SecurityEvents.ReadWrite.All";
"b9abcc4f-94fc-4457-9141-d20ce80ec952" = "SecurityIncident.Read.All";
"45cc0394-e837-488b-a098-1918f48d186c" = "SecurityIncident.Read.All";
"128ca929-1a19-45e6-a3b8-435ec44a36ba" = "SecurityIncident.ReadWrite.All";
"34bf0e97-1971-4929-b999-9e2442d941d7" = "SecurityIncident.ReadWrite.All";
"55896846-df78-47a7-aa94-8d3d4442ca7f" = "ServiceHealth.Read.All";
"79c261e0-fe76-4144-aad5-bdc68fbe4037" = "ServiceHealth.Read.All";
"eda39fa6-f8cf-4c3c-a909-432c683e4c9b" = "ServiceMessage.Read.All";
"1b620472-6534-4fe6-9df2-4680e8aa28ec" = "ServiceMessage.Read.All";
"636e1b0b-1cc2-4b1c-9aa9-4eeed9b9761b" = "ServiceMessageViewpoint.Write";
"9f9ce928-e038-4e3b-8faf-7b59049a8ddc" = "ServicePrincipalEndpoint.Read.All";
"5256681e-b7f6-40c0-8447-2d9db68797a0" = "ServicePrincipalEndpoint.Read.All";
"7297d82c-9546-4aed-91df-3d4f0a9b3ff0" = "ServicePrincipalEndpoint.ReadWrite.All";
"89c8469c-83ad-45f7-8ff2-6e3d4285709e" = "ServicePrincipalEndpoint.ReadWrite.All";
"2ef70e10-5bfd-4ede-a5f6-67720500b258" = "SharePointTenantSettings.Read.All";
"83d4163d-a2d8-4d3b-9695-4ae3ca98f888" = "SharePointTenantSettings.Read.All";
"aa07f155-3612-49b8-a147-6c590df35536" = "SharePointTenantSettings.ReadWrite.All";
"19b94e34-907c-4f43-bde9-38b1909ed408" = "SharePointTenantSettings.ReadWrite.All";
"50f66e47-eb56-45b7-aaa2-75057d9afe08" = "ShortNotes.Read";
"0c7d31ec-31ca-4f58-b6ec-9950b6b0de69" = "ShortNotes.Read.All";
"328438b7-4c01-4c07-a840-e625a749bb89" = "ShortNotes.ReadWrite";
"842c284c-763d-4a97-838d-79787d129bab" = "ShortNotes.ReadWrite.All";
"5a54b8b3-347c-476d-8f8e-42d5c7424d29" = "Sites.FullControl.All";
"a82116e5-55eb-4c41-a434-62fe8a61c773" = "Sites.FullControl.All";
"65e50fdc-43b7-4915-933e-e8138f11f40a" = "Sites.Manage.All";
"0c0bf378-bf22-4481-8f81-9e89a9b4960a" = "Sites.Manage.All";
"205e70e5-aba6-4c52-a976-6d2d46c48043" = "Sites.Read.All";
"332a536c-c7ef-4017-ab91-336970924f0d" = "Sites.Read.All";
"89fe6a52-be36-487e-b7d8-d061c450a026" = "Sites.ReadWrite.All";
"9492366f-7969-46a4-8d15-ed1a20078fff" = "Sites.ReadWrite.All";
"883ea226-0bf2-4a8f-9f9d-92c9162a727d" = "Sites.Selected";
"258f6531-6087-4cc4-bb90-092c5fb3ed3f" = "SMTP.Send";
"9c3af74c-fd0f-4db4-b17a-71939e2a9d77" = "SubjectRightsRequest.Read.All";
"ee1460f0-368b-4153-870a-4e1ca7e72c42" = "SubjectRightsRequest.Read.All";
"2b8fcc74-bce1-4ae3-a0e8-60c53739299d" = "SubjectRightsRequest.ReadWrite.All";
"8387eaa4-1a3c-41f5-b261-f888138e6041" = "SubjectRightsRequest.ReadWrite.All";
"5f88184c-80bb-4d52-9ff2-757288b2e9b7" = "Subscription.Read.All";
"7aa02aeb-824f-4fbe-a3f7-611f751f5b55" = "Synchronization.Read.All";
"5ba43d2f-fa88-4db2-bd1c-a67c5f0fb1ce" = "Synchronization.Read.All";
"7bb27fa3-ea8f-4d67-a916-87715b6188bd" = "Synchronization.ReadWrite.All";
"9b50c33d-700f-43b1-b2eb-87e89b703581" = "Synchronization.ReadWrite.All";
"f45671fb-e0fe-4b4b-be20-3d3ce43f1bcb" = "Tasks.Read";
"f10e1f91-74ed-437f-a6fd-d6ae88e26c1f" = "Tasks.Read.All";
"88d21fd4-8e5a-4c32-b5e2-4a1c95f34f72" = "Tasks.Read.Shared";
"2219042f-cab5-40cc-b0d2-16b1540b4c5f" = "Tasks.ReadWrite";
"44e666d1-d276-445b-a5fc-8815eeb81d55" = "Tasks.ReadWrite.All";
"c5ddf11b-c114-4886-8558-8a4e557cd52b" = "Tasks.ReadWrite.Shared";
"7825d5d6-6049-4ce7-bdf6-3b8d53f4bcd0" = "Team.Create";
"23fc2474-f741-46ce-8465-674744c5c361" = "Team.Create";
"485be79e-c497-4b35-9400-0e3fa7f2a5d4" = "Team.ReadBasic.All";
"2280dda6-0bfd-44ee-a2f4-cb867cfc4c1e" = "Team.ReadBasic.All";
"2497278c-d82d-46a2-b1ce-39d4cdde5570" = "TeamMember.Read.All";
"660b7406-55f1-41ca-a0ed-0b035e182f3e" = "TeamMember.Read.All";
"4a06efd2-f825-4e34-813e-82a57b03d1ee" = "TeamMember.ReadWrite.All";
"0121dc95-1b9f-4aed-8bac-58c5ac466691" = "TeamMember.ReadWrite.All";
"2104a4db-3a2f-4ea0-9dba-143d457dc666" = "TeamMember.ReadWriteNonOwnerRole.All";
"4437522e-9a86-4a41-a7da-e380edd4a97d" = "TeamMember.ReadWriteNonOwnerRole.All";
"0e755559-83fb-4b44-91d0-4cc721b9323e" = "TeamsActivity.Read";
"70dec828-f620-4914-aa83-a29117306807" = "TeamsActivity.Read.All";
"7ab1d787-bae7-4d5d-8db6-37ea32df9186" = "TeamsActivity.Send";
"a267235f-af13-44dc-8385-c1dc93023186" = "TeamsActivity.Send";
"bf3fbf03-f35f-4e93-963e-47e4d874c37a" = "TeamsAppInstallation.ReadForChat";
"cc7e7635-2586-41d6-adaa-a8d3bcad5ee5" = "TeamsAppInstallation.ReadForChat.All";
"5248dcb1-f83b-4ec3-9f4d-a4428a961a72" = "TeamsAppInstallation.ReadForTeam";
"1f615aea-6bf9-4b05-84bd-46388e138537" = "TeamsAppInstallation.ReadForTeam.All";
"c395395c-ff9a-4dba-bc1f-8372ba9dca84" = "TeamsAppInstallation.ReadForUser";
"9ce09611-f4f7-4abd-a629-a05450422a97" = "TeamsAppInstallation.ReadForUser.All";
"e1408a66-8f82-451b-a2f3-3c3e38f7413f" = "TeamsAppInstallation.ReadWriteAndConsentForChat";
"6e74eff9-4a21-45d6-bc03-3a20f61f8281" = "TeamsAppInstallation.ReadWriteAndConsentForChat.All";
"946349d5-2a9d-4535-abc0-7beeacaedd1d" = "TeamsAppInstallation.ReadWriteAndConsentForTeam";
"b0c13be0-8e20-4bc5-8c55-963c23a39ce9" = "TeamsAppInstallation.ReadWriteAndConsentForTeam.All";
"a0e0e18b-8fb2-458f-8130-da2d7cab9c75" = "TeamsAppInstallation.ReadWriteAndConsentSelfForChat";
"ba1ba90b-2d8f-487e-9f16-80728d85bb5c" = "TeamsAppInstallation.ReadWriteAndConsentSelfForChat.All";
"4a6bbf29-a0e1-4a4d-a7d1-cef17f772975" = "TeamsAppInstallation.ReadWriteAndConsentSelfForTeam";
"1e4be56c-312e-42b8-a2c9-009600d732c0" = "TeamsAppInstallation.ReadWriteAndConsentSelfForTeam.All";
"aa85bf13-d771-4d5d-a9e6-bca04ce44edf" = "TeamsAppInstallation.ReadWriteForChat";
"9e19bae1-2623-4c4f-ab6e-2664615ff9a0" = "TeamsAppInstallation.ReadWriteForChat.All";
"2e25a044-2580-450d-8859-42eeb6e996c0" = "TeamsAppInstallation.ReadWriteForTeam";
"5dad17ba-f6cc-4954-a5a2-a0dcc95154f0" = "TeamsAppInstallation.ReadWriteForTeam.All";
"093f8818-d05f-49b8-95bc-9d2a73e9a43c" = "TeamsAppInstallation.ReadWriteForUser";
"74ef0291-ca83-4d02-8c7e-d2391e6a444f" = "TeamsAppInstallation.ReadWriteForUser.All";
"0ce33576-30e8-43b7-99e5-62f8569a4002" = "TeamsAppInstallation.ReadWriteSelfForChat";
"73a45059-f39c-4baf-9182-4954ac0e55cf" = "TeamsAppInstallation.ReadWriteSelfForChat.All";
"0f4595f7-64b1-4e13-81bc-11a249df07a9" = "TeamsAppInstallation.ReadWriteSelfForTeam";
"9f67436c-5415-4e7f-8ac1-3014a7132630" = "TeamsAppInstallation.ReadWriteSelfForTeam.All";
"207e0cb1-3ce7-4922-b991-5a760c346ebc" = "TeamsAppInstallation.ReadWriteSelfForUser";
"908de74d-f8b2-4d6b-a9ed-2a17b3b78179" = "TeamsAppInstallation.ReadWriteSelfForUser.All";
"48638b3c-ad68-4383-8ac4-e6880ee6ca57" = "TeamSettings.Read.All";
"242607bd-1d2c-432c-82eb-bdb27baa23ab" = "TeamSettings.Read.All";
"39d65650-9d3e-4223-80db-a335590d027e" = "TeamSettings.ReadWrite.All";
"bdd80a03-d9bc-451d-b7c4-ce7c63fe3c8f" = "TeamSettings.ReadWrite.All";
"a9ff19c2-f369-4a95-9a25-ba9d460efc8e" = "TeamsTab.Create";
"49981c42-fd7b-4530-be03-e77b21aed25e" = "TeamsTab.Create";
"59dacb05-e88d-4c13-a684-59f1afc8cc98" = "TeamsTab.Read.All";
"46890524-499a-4bb2-ad64-1476b4f3e1cf" = "TeamsTab.Read.All";
"b98bfd41-87c6-45cc-b104-e2de4f0dafb9" = "TeamsTab.ReadWrite.All";
"a96d855f-016b-47d7-b51c-1218a98d791c" = "TeamsTab.ReadWrite.All";
"ee928332-e9c2-4747-b4a0-f8c164b68de6" = "TeamsTab.ReadWriteForChat";
"fd9ce730-a250-40dc-bd44-8dc8d20f39ea" = "TeamsTab.ReadWriteForChat.All";
"c975dd04-a06e-4fbb-9704-62daad77bb49" = "TeamsTab.ReadWriteForTeam";
"6163d4f4-fbf8-43da-a7b4-060fe85ed148" = "TeamsTab.ReadWriteForTeam.All";
"c37c9b61-7762-4bff-a156-afc0005847a0" = "TeamsTab.ReadWriteForUser";
"425b4b59-d5af-45c8-832f-bb0b7402348a" = "TeamsTab.ReadWriteForUser.All";
"0c219d04-3abf-47f7-912d-5cca239e90e6" = "TeamsTab.ReadWriteSelfForChat";
"9f62e4a2-a2d6-4350-b28b-d244728c4f86" = "TeamsTab.ReadWriteSelfForChat.All";
"f266662f-120a-4314-b26a-99b08617c7ef" = "TeamsTab.ReadWriteSelfForTeam";
"91c32b81-0ef0-453f-a5c7-4ce2e562f449" = "TeamsTab.ReadWriteSelfForTeam.All";
"395dfec1-a0b9-465f-a783-8250a430cb8c" = "TeamsTab.ReadWriteSelfForUser";
"3c42dec6-49e8-4a0a-b469-36cff0d9da93" = "TeamsTab.ReadWriteSelfForUser.All";
"cd87405c-5792-4f15-92f7-debc0db6d1d6" = "TeamTemplates.Read";
"6323133e-1f6e-46d4-9372-ac33a0870636" = "TeamTemplates.Read.All";
"dfb0dd15-61de-45b2-be36-d6a69fba3c79" = "Teamwork.Migrate.All";
"44e060c4-bbdc-4256-a0b9-dcc0396db368" = "TeamworkAppSettings.Read.All";
"475ebe88-f071-4bd7-af2b-642952bd4986" = "TeamworkAppSettings.Read.All";
"87c556f0-2bd9-4eed-bd74-5dd8af6eaf7e" = "TeamworkAppSettings.ReadWrite.All";
"ab5b445e-8f10-45f4-9c79-dd3f8062cc4e" = "TeamworkAppSettings.ReadWrite.All";
"b659488b-9d28-4208-b2be-1c6652b3c970" = "TeamworkDevice.Read.All";
"0591bafd-7c1c-4c30-a2a5-2b9aacb1dfe8" = "TeamworkDevice.Read.All";
"ddd97ecb-5c31-43db-a235-0ee20e635c40" = "TeamworkDevice.ReadWrite.All";
"79c02f5b-bd4f-4713-bc2c-a8a4a66e127b" = "TeamworkDevice.ReadWrite.All";
"57587d0b-8399-45be-b207-8050cec54575" = "TeamworkTag.Read";
"b74fd6c4-4bde-488e-9695-eeb100e4907f" = "TeamworkTag.Read.All";
"539dabd7-b5b6-4117-b164-d60cd15a8671" = "TeamworkTag.ReadWrite";
"a3371ca5-911d-46d6-901c-42c8c7a937d8" = "TeamworkTag.ReadWrite.All";
"297f747b-0005-475b-8fef-c890f5152b38" = "TermStore.Read.All";
"ea047cc2-df29-4f3e-83a3-205de61501ca" = "TermStore.Read.All";
"6c37c71d-f50f-4bff-8fd3-8a41da390140" = "TermStore.ReadWrite.All";
"f12eb8d6-28e3-46e6-b2c0-b7e4dc69fc95" = "TermStore.ReadWrite.All";
"f8f035bb-2cce-47fb-8bf5-7baf3ecbee48" = "ThreatAssessment.Read.All";
"cac97e40-6730-457d-ad8d-4852fddab7ad" = "ThreatAssessment.ReadWrite.All";
"b152eca8-ea73-4a48-8c98-1a6742673d99" = "ThreatHunting.Read.All";
"dd98c7f5-2d42-42d3-a0e4-633161547251" = "ThreatHunting.Read.All";
"9cc427b4-2004-41c5-aa22-757b755e9796" = "ThreatIndicators.Read.All";
"197ee4e9-b993-4066-898f-d6aecc55125b" = "ThreatIndicators.Read.All";
"91e7d36d-022a-490f-a748-f8e011357b42" = "ThreatIndicators.ReadWrite.OwnedBy";
"21792b6c-c986-4ffc-85de-df9da54b52fa" = "ThreatIndicators.ReadWrite.OwnedBy";
"fd5353c6-26dd-449f-a565-c4e16b9fce78" = "ThreatSubmission.Read";
"7083913a-4966-44b6-9886-c5822a5fd910" = "ThreatSubmission.Read.All";
"86632667-cd15-4845-ad89-48a88e8412e1" = "ThreatSubmission.Read.All";
"68a3156e-46c9-443c-b85c-921397f082b5" = "ThreatSubmission.ReadWrite";
"8458e264-4eb9-4922-abe9-768d58f13c7f" = "ThreatSubmission.ReadWrite.All";
"d72bdbf4-a59b-405c-8b04-5995895819ac" = "ThreatSubmission.ReadWrite.All";
"059e5840-5353-4c68-b1da-666a033fc5e8" = "ThreatSubmissionPolicy.ReadWrite.All";
"926a6798-b100-4a20-a22f-a4918f13951d" = "ThreatSubmissionPolicy.ReadWrite.All";
"7ad34336-f5b1-44ce-8682-31d7dfcd9ab9" = "TrustFrameworkKeySet.Read.All";
"fff194f1-7dce-4428-8301-1badb5518201" = "TrustFrameworkKeySet.Read.All";
"39244520-1e7d-4b4a-aee0-57c65826e427" = "TrustFrameworkKeySet.ReadWrite.All";
"4a771c9a-1cf2-4609-b88e-3d3e02d539cd" = "TrustFrameworkKeySet.ReadWrite.All";
"73e75199-7c3e-41bb-9357-167164dbb415" = "UnifiedGroupMember.Read.AsGuest";
"405a51b5-8d8d-430b-9842-8be4b0e9f324" = "User.Export.All";
"63dd7cd9-b489-4adf-a28c-ac38b9a0f962" = "User.Invite.All";
"09850681-111b-4a89-9bed-3f2cae46d706" = "User.Invite.All";
"637d7bec-b31e-4deb-acc9-24275642a2c9" = "User.ManageIdentities.All";
"c529cfca-c91b-489c-af2b-d92990b66ce6" = "User.ManageIdentities.All";
"e1fe6dd8-ba31-4d61-89e7-88639da4683d" = "User.Read";
"a154be20-db9c-4678-8ab7-66f6cc099a59" = "User.Read.All";
"df021288-bdef-4463-88db-98f22de89214" = "User.Read.All";
"b340eb25-3456-403f-be2f-af7a0d370277" = "User.ReadBasic.All";
"97235f07-e226-4f63-ace3-39588e11d3a1" = "User.ReadBasic.All";
"b4e74841-8e56-480b-be8b-910348b18b4c" = "User.ReadWrite";
"204e0828-b5ca-4ad8-b9f3-f32a958e7cc4" = "User.ReadWrite.All";
"741f803b-c850-494e-b5df-cde7c675a1ca" = "User.ReadWrite.All";
"47607519-5fb1-47d9-99c7-da4b48f369b1" = "UserActivity.ReadWrite.CreatedByApp";
"1f6b61c5-2f65-4135-9c9f-31c0f8d32b52" = "UserAuthenticationMethod.Read";
"aec28ec7-4d02-4e8c-b864-50163aea77eb" = "UserAuthenticationMethod.Read.All";
"38d9df27-64da-44fd-b7c5-a6fbac20248f" = "UserAuthenticationMethod.Read.All";
"48971fc1-70d7-4245-af77-0beb29b53ee2" = "UserAuthenticationMethod.ReadWrite";
"b7887744-6746-4312-813d-72daeaee7e2d" = "UserAuthenticationMethod.ReadWrite.All";
"50483e42-d915-4231-9639-7fdb7fd190e5" = "UserAuthenticationMethod.ReadWrite.All";
"ed8d2a04-0374-41f1-aefe-da8ac87ccc87" = "User-LifeCycleInfo.Read.All";
"8556a004-db57-4d7a-8b82-97a13428e96f" = "User-LifeCycleInfo.Read.All";
"7ee7473e-bd4b-4c9f-987c-bd58481f5fa2" = "User-LifeCycleInfo.ReadWrite.All";
"925f1248-0f97-47b9-8ec8-538c54e01325" = "User-LifeCycleInfo.ReadWrite.All";
"26e2f3e8-b2a1-47fc-9620-89bb5b042024" = "UserNotification.ReadWrite.CreatedByApp";
"4e774092-a092-48d1-90bd-baad67c7eb47" = "UserNotification.ReadWrite.CreatedByApp";
"de023814-96df-4f53-9376-1e2891ef5a18" = "UserShiftPreferences.Read.All";
"d1eec298-80f3-49b0-9efb-d90e224798ac" = "UserShiftPreferences.ReadWrite.All";
"367492fc-594d-4972-a9b5-0d58c622c91c" = "UserTimelineActivity.Write.CreatedByApp";
"27470298-d3b8-4b9c-aad4-6334312a3eac" = "VirtualAppointment.Read";
"d4f67ec2-59b5-4bdc-b4af-d78f6f9c1954" = "VirtualAppointment.Read.All";
"2ccc2926-a528-4b17-b8bb-860eed29d64c" = "VirtualAppointment.ReadWrite";
"bf46a256-f47d-448f-ab78-f226fff08d40" = "VirtualAppointment.ReadWrite.All";
"11776c0c-6138-4db3-a668-ee621bea2555" = "WindowsUpdates.ReadWrite.All";
"7dd1be58-6e76-4401-bf8d-31d1e8180d5b" = "WindowsUpdates.ReadWrite.All";
"f1ccd5a7-6383-466a-8db8-1a656f7d06fa" = "WorkforceIntegration.Read.All";
"08c4b377-0d23-4a8b-be2a-23c1c1d88545" = "WorkforceIntegration.ReadWrite.All";
"202bf709-e8e6-478e-bcfd-5d63c50b68e3" = "WorkforceIntegration.ReadWrite.All";
}

# An in-memory cache of objects by {object ID} andy by {object class, object ID}
$script:ObjectByObjectId = @{}
$script:CachedUserList = @{}

# Function to add an object to the cache
function CacheObject ($Object) {
    if ($Object) {
        $script:ObjectByObjectId[$Object.Id] = $Object
    }
}

# Function to add a user to the cache
function CacheUser ($User) {
    if ($User) {
        $script:CachedUserList[$User.Id] = $User
    }
}

# Function to retrieve an object from the cache (if it's there), or from Azure AD (if not).
function GetObjectByObjectId ($ObjectId) {
    if (-not $script:ObjectByObjectId.ContainsKey($ObjectId)) {
        Write-Verbose ("Querying Azure AD for object '{0}'" -f $ObjectId)
        try {
            $object = Get-MgDirectoryObjectById -Ids $ObjectId
            CacheObject -Object $object
        } catch {
            Write-Verbose "Object not found."
        }
    }
    return $script:ObjectByObjectId[$ObjectId]
}

# Function to retrieve an object from the cache (if it's there), or from Azure AD (if not).
function GetUserById ($UserId) {
    if (-not $script:CachedUserList.ContainsKey($UserId)) {
        Write-Verbose ("Querying Azure AD for user '{0}'" -f $UserId)
        try {
            $user = Get-MgUser -UserId $UserId
            CacheUser -User $user
        } catch {
            Write-Verbose "User not found."
        }
    }
    return $script:CachedUserList[$UserId]
}

# Function to retrieve all OAuth2PermissionGrants, either by directly listing them (-FastMode)
# or by iterating over all ServicePrincipal objects. The latter is required if there are more than
# 999 OAuth2PermissionGrants in the tenant, due to a bug in Azure AD.
function GetOAuth2PermissionGrants ([switch]$FastMode) {
    if ($FastMode) {
        Get-MgOauth2PermissionGrant -All
    } else {
        $script:ObjectByObjectId.GetEnumerator() | ForEach-Object { $i = 0 } {
            if ($ShowProgress) {
                Write-Progress -Activity "Retrieving delegated permissions..." `
                               -Status ("Checked {0}/{1} apps" -f $i++, $servicePrincipalCount) `
                               -PercentComplete (($i / $servicePrincipalCount) * 100)
            }

            $client = $_.Value
            Get-MgServicePrincipalOauth2PermissionGrant -ServicePrincipalId $client.Id
        }
    }
}

$empty = @{} # Used later to avoid null checks

# Get all ServicePrincipal objects and add to the cache
Write-Verbose "Retrieving all ServicePrincipal objects..."
Get-MgServicePrincipal -All | ForEach-Object {
    CacheObject -Object $_
}
$servicePrincipalCount = $script:ObjectByObjectId.Count

Write-Verbose ("{0} ServicePrincipal objects have been cached" -f $servicePrincipalCount)

if ($DelegatedPermissions -or (-not ($DelegatedPermissions -or $ApplicationPermissions))) {

    # Get one page of User objects and add to the cache
    Write-Verbose ("Retrieving up to {0} User objects..." -f $PrecacheSize)
	
    Get-MgUser -Top $PrecacheSize | ForEach-Object {
         CacheUser -User $_
    }

    Write-Verbose ("{0} User objects have been cached" -f $script:CachedUserList.Count)

    Write-Verbose "Testing for OAuth2PermissionGrants bug before querying..."
    $fastQueryMode = $false
    try {
        # There's a bug in Azure AD Graph which does not allow for directly listing
        # oauth2PermissionGrants if there are more than 999 of them. The following line will
        # trigger this bug (if it still exists) and throw an exception.
        $null = Get-MgOauth2PermissionGrant -Top 999
        $fastQueryMode = $true
    } catch {
        if ($_.Exception.Message -and $_.Exception.Message.StartsWith("Unexpected end when deserializing array.")) {
            Write-Verbose ("Fast query for delegated permissions failed, using slow method...")
        } else {
            throw $_
        }
    }

    # Get all existing OAuth2 permission grants, get the client, resource and scope details
    Write-Verbose "Retrieving OAuth2PermissionGrants..."
    GetOAuth2PermissionGrants -FastMode:$fastQueryMode | ForEach-Object {
        $grant = $_
        $app = Get-MgServicePrincipal -ServicePrincipalId $grant.ClientId
        if ($grant.Scope) {
            $grant.Scope.Split(" ") | Where-Object { $_ } | ForEach-Object {
                $scope = $_
                if ($ShowProgress) {
                    Write-Progress -Activity "Retrieving SP permissions..." `
                                -Status ("Checked {0}/{1} SPs" -f $i++, $servicePrincipalCount) `
                                -PercentComplete (($i / $servicePrincipalCount) * 100)
                }
                $grantDetails =  [ordered]@{
                    "PermissionType" = "Delegated"
                    "ClientName" = $app.DisplayName
                    "ClientObjectId" = $grant.ClientId
                    "ResourceObjectId" = $grant.ResourceId
                    "Permission" = $scope
                    "ConsentType" = $grant.ConsentType
                    "PrincipalObjectId" = $grant.PrincipalId
                }

                # Add properties for principal (will all be null if there's no principal)
                if ($UserProperties.Count -gt 0) {

                    $principal = $empty
                    if ($grant.PrincipalId) {
                       $principal = GetUserById($grant.PrincipalId)
                    }

                    foreach ($propertyName in $UserProperties) {
                        $grantDetails["Principal$propertyName"] = $principal.$propertyName
                    }
                }

                New-Object PSObject -Property $grantDetails
            }
        }
    }
}

if ($ApplicationPermissions -or (-not ($DelegatedPermissions -or $ApplicationPermissions))) {

    # Iterate over all ServicePrincipal objects and get app permissions
    Write-Verbose "Retrieving AppRoleAssignments..."
    $script:ObjectByObjectId.GetEnumerator() | ForEach-Object { $i = 0 } {

        if ($ShowProgress) {
            Write-Progress -Activity "Retrieving application permissions..." `
                        -Status ("Checked {0}/{1} apps" -f $i++, $servicePrincipalCount) `
                        -PercentComplete (($i / $servicePrincipalCount) * 100)
        }

        $sp = $_.Value

        Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $sp.Id -All  `
        | Where-Object { $_.PrincipalType -eq "ServicePrincipal" } | ForEach-Object {
            $assignment = $_
            $app = Get-MgServicePrincipal -ServicePrincipalId $assignment.PrincipalId
            $grantDetails = [ordered]@{
                "PermissionType" = "Application"
                "ClientName" = $app.DisplayName
                "ClientObjectId" = $assignment.PrincipalId
                "ResourceObjectId" = $assignment.ResourceId
                "ResourceDisplayName" = $assignment.ResourceDisplayName
                "Permission" = $permission_lookup[$assignment.AppRoleId]
            }

            New-Object PSObject -Property $grantDetails
        }
    }
}