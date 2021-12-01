###############
# DESCRIPTION #
###############

# This Runbook searchs Azure ARC Servers with CustomScriptExtension and key tag "POLICY_RESTART" and deletes old CustomScriptExtensions

##########
# SCRIPT #
##########

Import-Module Az.ResourceGraph

# Connect to Azure with Automation Account system-assigned managed identity
Disable-AzContextAutosave -Scope Process
$AzureContext = (Connect-AzAccount -Identity -WarningAction Ignore).context
$AzureContext = Set-AzContext -SubscriptionName $AzureContext.Subscription -DefaultProfile $AzureContext

# Search Azure ARC Servers with POLICY_RESTART tag and CustomScriptExtension
$azureArcServersQueryParam = @{
    Query = 'resources
    | where type == "microsoft.hybridcompute/machines"
    | where isnotnull(tags["POLICY_RESTART"])
    | extend
        JoinID = toupper(id),
        VmRG = tostring(resourceGroup)
    | join kind=leftouter(
        Resources
        | where type == "microsoft.hybridcompute/machines/extensions"
        | extend
            VMId = toupper(substring(id, 0, indexof(id, "/extensions")))
    ) on $left.JoinID == $right.VMId
    | project subscriptionId, resourceGroup, arcServerName=name, VmExtensionName=name1
    | where isnotempty(VmExtensionName)
    | where VmExtensionName in ("CustomScript", "CustomScriptExtension")'
}

$azureArcServersExtensionsToBeDeleted = Search-AzGraph @azureArcServersQueryParam

foreach ($azureArcServerExtension in $azureArcServersExtensionsToBeDeleted)
{
    Write-Output "============"
    Write-Output "Subscription Id: $($azureArcServerExtension.subscriptionId)"
    Write-Output "resourceGroup: $($azureArcServerExtension.resourceGroup)"
    Write-Output "arcServerName: $($azureArcServerExtension.arcServerName)"
    Write-Output "VmExtensionName: $($azureArcServerExtension.VmExtensionName)"
    
    Select-AzSubscription -SubscriptionId $azureArcServerExtension.subscriptionId
    Remove-AzConnectedMachineExtension -MachineName $azureArcServerExtension.arcServerName -ResourceGroupName $azureArcServerExtension.resourceGroup -Name $azureArcServerExtension.VmExtensionName
}
