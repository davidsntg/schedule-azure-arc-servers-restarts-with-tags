<#

.PARAMETER subscriptionId
.PARAMETER resourceGroup
.PARAMETER machineName
.PARAMETER location
.PARAMETER osType
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$subscriptionId = "",

    [Parameter(Mandatory = $true)]
    [string]$resourceGroup = "",

    [Parameter(Mandatory = $true)]
    [string]$machineName = "",

    [Parameter(Mandatory = $true)]
    [string]$location = "",

    [Parameter(Mandatory = $true)]
    [string]$osType = ""
)

###############
# DESCRIPTION #
###############

# This Runbook installs CustomScript Extension on Azure Arc Servers to reboot the machines

#################
# CONFIGURATION #
#################

# Windows Azure ARC Servers - Settings
$windowsSettings = '{"fileUris": ["https://raw.githubusercontent.com/dawlysd/schedule-azure-arc-servers-restarts-with-tags/main/scripts/azurearcservers-restartwindows.ps1"]}'
$windowsProtectedSettings = '{"commandToExecute": "powershell -ExecutionPolicy Unrestricted -File azurearcservers-restartwindows.ps1"}'

# Linux Azure ARC Servers - Settings
$linuxSettings = '{"commandToExecute":"sudo sh azurearcservers-restartlinux.sh", "fileUris": ["https://raw.githubusercontent.com/dawlysd/schedule-azure-arc-servers-restarts-with-tags/main/scripts/azurearcservers-restartlinux.sh"]}'

##########
# SCRIPT #
##########

Import-Module Az.ConnectedMachine

# Connect to Azure with Automation Account system-assigned managed identity
Disable-AzContextAutosave -Scope Process
$AzureContext = (Connect-AzAccount -Identity -WarningAction Ignore).context
$AzureContext = Set-AzContext -SubscriptionName $AzureContext.Subscription -DefaultProfile $AzureContext

Select-AzSubscription -SubscriptionId $subscriptionId

if ($osType -eq "linux")
{
    $extensionName = "CustomScript"
    $extensionType = "CustomScript" 
    $publisher = "Microsoft.Azure.Extensions"
    
    New-AzConnectedMachineExtension -MachineName $machineName -ResourceGroupName $resourceGroup -Location $location -Name $extensionName -Setting $linuxSettings -ExtensionType $extensionType -Publisher $publisher    
}
elseif ($osType -eq "windows") {
    $extensionName = "CustomScriptExtension"
    $extensionType = "CustomScriptExtension" 
    $publisher = "Microsoft.Compute"
    New-AzConnectedMachineExtension -MachineName $machineName -ResourceGroupName $resourceGroup -Location $location -Name $extensionName -Setting $windowsSettings -ExtensionType $extensionType -Publisher $publisher -ProtectedSetting $windowsProtectedSettings
}
else {
    Write-Error "Os Type unknown for machine $($machineName): $($osType)"
}

Write-Output "Done."

