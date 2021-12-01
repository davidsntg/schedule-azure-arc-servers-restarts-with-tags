###############
# DESCRIPTION #
###############

# This Runbook searchs Azure ARC Servers with key tag "POLICY_RESTART"
# If an Azure ARC Server has a "POLICY_RESTART" key tag, a restart job will be created in the current automation account.
# Restart job will just install Azure ARC Server extension which will execute powershell or bash script to reboot machine.
# Name of the extension for Windows:
# Name of the extension for Linux:

# Syntax of "POLICY_RESTART" key tag:
# DaysOfWeek;rebootTime

# Example #1 - POLICY_RESTART: Monday,Wednesday;07h00 PM
# Example #2 - POLICY_RESTART: Saturday;06h00 AM

# Requirements
# Az.ConnectedMachine module must be installed on the Automation Account (powershell cmd: Install-Module -Name Az.ConnectedMachine)

#################
# CONFIGURATION #
#################

# TimeZone - Can be the IANA ID or the Windows Time Zone ID
$timezone = "Romance Standard Time" # France - Central European Time

# Valid days of week - used to check tags values.
$validDaysOfWeek = @("Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday")

# Schedule name prefix for Azure Arc Server
$schedulePrefix = "ArcServers-ScheduleRestart-"

# Reboot Runbook name
$rebootRunbookName = "ArcServers-RestartMachine"

##########
# SCRIPT #
##########

Import-Module Az.ResourceGraph

# Connect to Azure with Automation Account system-assigned managed identity
Disable-AzContextAutosave -Scope Process
$AzureContext = (Connect-AzAccount -Identity -WarningAction Ignore).context
$AzureContext = Set-AzContext -SubscriptionName $AzureContext.Subscription -DefaultProfile $AzureContext

# Get current automation account
$automationAccountsQuery = @{
    Query = "resources
| where type == 'microsoft.automation/automationaccounts'"
}
$automationAccounts = Search-AzGraph @automationAccountsQuery

foreach ($automationAccount in $automationAccounts)
{
    Select-AzSubscription -SubscriptionId $automationAccount.subscriptionId
    $Job = Get-AzAutomationJob -ResourceGroupName $automationAccount.resourceGroup -AutomationAccountName $automationAccount.name -Id $PSPrivateMetadata.JobId.Guid -ErrorAction SilentlyContinue
    if (!([string]::IsNullOrEmpty($Job)))
    {
        $automationAccountSubscriptionId = $automationAccount.subscriptionId
        $automationAccountRg = $Job.ResourceGroupName
        $automationAccountName = $Job.AutomationAccountName
        break;
    }
}

# Search Azure ARC Servers with POLICY_RESTART tag
 $azureArcServersQueryParam = @{
    Query = "resources
    | where type == 'microsoft.hybridcompute/machines'
    | where isnotnull(tags['POLICY_RESTART'])
    | project id, name, policy_restart=tags['POLICY_RESTART'], osType=properties.osType, location"
}

$azureArcServersToBeScheduleForReboot = Search-AzGraph @azureArcServersQueryParam

foreach ($azureArcServer in $azureArcServersToBeScheduleForReboot)
{
    $machineId = $azureArcServer.id
    $machineSubscription = $machineId.Split('/')[2]
    $machineResourceGroup = $machineId.Split('/')[4]
    $machineName = $azureArcServer.name
    $machineosType = $azureArcServer.osType
    $machineRestartPolicy = $azureArcServer.policy_restart
    $machineLocation = $azureArcServer.location

    $DaysOfWeek = $machineRestartPolicy.Split(";")[0].Split(',')
    foreach($day in $DaysOfWeek)
    {
        if (!$validDaysOfWeek.contains($day))
        {
            Write-Error "/!\ Error! DaysOfWeek is not valid. It should be Monday, Tuesday, Wednesday, Thursday, Friday, Saturday or Sunday. Current value for VM $($machineName): $($DaysOfWeek)"
            continue
        }
    }
    $startTime = $machineRestartPolicy.Split(";")[1]
    try {
        $startTime = (Get-Date $startTime).AddDays(1)
    }
    catch {
        Write-Error "/!\ Error! startTime is not valid. It should be 'hh:mm AM' or 'hh:mm PM' formatted. Current value for VM $($machineName): $($startTime)"
        continue
    }

    # Create Weekly Deployment Schedule
    $scheduleName = "$($schedulePrefix)$($machineName)"
    New-AzAutomationSchedule -ResourceGroupName $automationAccountRg `
        -AutomationAccountName $automationAccountName `
        -Name "$($scheduleName)" `
        -StartTime $startTime `
        -TimeZone $timezone `
        -DaysOfWeek $DaysOfWeek `
        -WeekInterval 1

    $parameters= @{
        "machineName" = $machineName
        "resourceGroup" = $machineResourceGroup
        "location" = $machineLocation
        "subscriptionId" = $machineSubscription
        "osType" = $machineosType
    }

    Write-Output "========="
    Write-Output "Machine Id: $($machineId)"
    Write-Output "Machine Subscription: $($machineSubscription)"
    Write-Output "Machine RG: $($machineResourceGroup)"
    Write-Output "Machine Name: $($machineName)"
    Write-Output "Machine osType: $($machineosType)"
    Write-Output "Machine Restart Policy: $($machineRestartPolicy)"
    Write-Output "Machine Location: $($machineLocation)"
    Write-Output "========="

    # Link the Reboot Runbook with created schedule
    Register-AzAutomationScheduledRunbook -AutomationAccountName $automationAccountName -Name $rebootRunbookName -ScheduleName "$($scheduleName)" -ResourceGroupName $automationAccountRg -Parameters $parameters
    
}

Write-Output "Done"
