<#
.SYNOPSIS
    Script to Create VHD Images From Specialized VMs Using Snapshot

.DESCRIPTION
    This script will Create VHD Images From Specialized VMs Using Snapshot
    You will be prompted to select VMs and Storage Accounts.
    You will also be able to create new storage accounts and containers to use.
    VMs selected will be powered off and snapshots will be created of all disks.
    Snapshots will then be copied to the Storage Account & Container you choose.
    The snapshots will then be removed and the VM will be returned to its initial power state.

.EXAMPLE
    .\Create-VHDImagesFromSpecializedVMsUsingSnapshot.ps1
#>
[CmdletBinding()]
Param
(

)

$VerbosePreference = 'Continue'

Function Invoke-ResourceNameAvailability
{
    [CmdletBinding()]
    Param 
    (
        
        [Parameter(Mandatory=$true,HelpMessage="Provide your Subscription ID. Example ddce26e8-4d72-4881-ae59-4b34d999528d")]
        $SubscriptionID,

        [Parameter(Mandatory=$true,HelpMessage="Specify the Name for the Resource. Example storageaccountname")]
        $ResourceName,

        [Parameter(Mandatory=$true,HelpMessage="Example Microsoft.Storage")]
        $ResourceKind,

        [Parameter(Mandatory=$true,HelpMessage="Example Microsoft.Storage/storageAccounts")]
        $ResourceType
    )

    $AzureContext = Get-AzContext
    $restUri = $($AzureContext.Environment.ResourceManagerUrl) + "/subscriptions/$SubscriptionID/providers/$ResourceKind/checkNameAvailability?api-version=2017-10-01"
    
    $AuthHeader = Invoke-CreateAuthHeader
    $Body= @{
        'Name' = "$ResourceName"
        'Type' = "$ResourceType"
    } | ConvertTo-Json
    $Results = Invoke-RestMethod -Uri $restUri -Method Post -Headers $AuthHeader -Body $Body
    return $Results
}

Function Invoke-ResourceGroupSelectionCreation
{
    [CmdletBinding()]
    Param 
    (
        [Parameter(Mandatory=$true,HelpMessage='Provide a message to be displayed in the selection window.')]
        [String]$ResourceGroupMessage,

        $Location
    )

    $ResourceGroups = @()
    $ResourceGroups += 'New'
    $ResourceGroups += (Get-AzResourceGroup).ResourceGroupName

    $ResourceGroupNameCheckRegEx = '^[-\w\._\(\)]*[-\w_\(\)]$'

    $ResourceGroupName = $ResourceGroups | Out-GridView -Title "$ResourceGroupMessage" -PassThru

    if ($ResourceGroupName -eq 'New')
    {
        # Create Resource Group
        $ResourceNameAvailability = $false
        $ResourceNameValidation = $false
                    
        do 
        {
            $ResourceGroupName = Read-Host "Please Enter a name for the Resource Group"
                
            if (($ResourceGroupName -match $ResourceGroupNameCheckRegEx) -and ($ResourceGroupName.Length -ge 1) -and ($ResourceGroupName.Length -lt 80))
            {
                $ResourceNameValidation = $true
                $ResourceNameAvailabilityCheck = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
            }

            if ($ResourceGroupName -notmatch $ResourceGroupNameCheckRegEx)
            {
                Write-Warning -Message 'Resource group names only allow alphanumeric characters, periods, underscores, hyphens and parenthesis and cannot end in a period.'
            }

            if (($ResourceGroupName.Length -lt 1) -or ($ResourceGroupName.Length -gt 90))
            {
                Write-Warning -Message 'Resource Group Names may only be between 1 and 90 characters'
            }
                
            if ($ResourceNameAvailabilityCheck)
            {
                Write-Warning -Message "Resource Group Name $ResourceGroupName Already Exists"
                Write-Warning -Message "Please Choose Another Name"
                $ResourceNameAvailabilityCheck = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
            }

            else
            {
                $ResourceNameAvailability = $true
            }

        } 
        until (($ResourceNameAvailability -eq $true) -and ($ResourceNameValidation -eq $true))

        $ResourceGroup = New-AzResourceGroup -Name $ResourceGroupName -Location $Location -Verbose
    }
    else 
    {
        $ResourceGroup = Get-AzResourceGroup -Name $ResourceGroupName
    }

    return $ResourceGroup

}

Function Invoke-StorageAccountSelectionCreation
{
    [CmdletBinding()]
    Param 
    (
        $Location
    )
    
    $StorageAccounts = @()
    $StorageAccounts += 'New'
    $StorageAccounts += (Get-AzStorageAccount).StorageAccountName
    $DestinationStorageAccountName = $StorageAccounts | Out-GridView -Title "Please Select an existing or new storage account for Image Storage." -PassThru

    If ($DestinationStorageAccountName -eq 'New')
    {
        $ResourceGroups = @()
        $ResourceGroups += 'New'
        $ResourceGroups += (Get-AzResourceGroup).ResourceGroupName

        $ResourceGroupNameCheckRegEx = '^[-\w\._\(\)]*[-\w_\(\)]$'

        $StorageAccountResourceGroupName = $ResourceGroups | Out-GridView -Title "Please Select an existing or new Resource Group for the Storage Account." -PassThru

        if ($StorageAccountResourceGroupName -eq 'New')
        {
            # Create Resource Group
            $ResourceNameAvailability = $false
            $ResourceNameValidation = $false
                    
            do 
            {
                $StorageAccountResourceGroupName = Read-Host "Please Enter a name for the Resource Group"
                
                if (($StorageAccountResourceGroupName -match $ResourceGroupNameCheckRegEx) -and ($StorageAccountResourceGroupName.Length -ge 1) -and ($StorageAccountResourceGroupName.Length -lt 80))
                {
                    $ResourceNameValidation = $true
                    $ResourceNameAvailabilityCheck = Get-AzResourceGroup -Name $StorageAccountResourceGroupName -ErrorAction SilentlyContinue
                }
                if ($StorageAccountResourceGroupName -notmatch $ResourceGroupNameCheckRegEx)
                {
                    Write-Warning -Message 'Resource group names only allow alphanumeric characters, periods, underscores, hyphens and parenthesis and cannot end in a period.'
                }
                if (($StorageAccountResourceGroupName.Length -lt 1) -or ($StorageAccountResourceGroupName.Length -gt 90))
                {
                    Write-Warning -Message 'Resource Group Names may only be between 1 and 90 characters'
                }
                
                if ($ResourceNameAvailabilityCheck)
                {
                    Write-Warning -Message "Resource Group Name $StorageAccountResourceGroupName Already Exists"
                    Write-Warning -Message "Please Choose Another Name"
                    $ResourceNameAvailabilityCheck = Get-AzResourceGroup -Name $StorageAccountResourceGroupName -ErrorAction SilentlyContinue
                }
                else
                {
                    $ResourceNameAvailability = $true
                }

            } 
            until (($ResourceNameAvailability -eq $true) -and ($ResourceNameValidation -eq $true))

            $StorageAccountResourceGroup = New-AzResourceGroup -Name $StorageAccountResourceGroupName -Location $Location -Verbose
        }
        else 
        {
            $StorageAccountResourceGroup = Get-AzResourceGroup -Name $StorageAccountResourceGroupName
        }

        # Create Storage Account
        $ResourceNameAvailability = $false
        $ResourceKind = 'Microsoft.Storage'
        $ResourceType = 'Microsoft.Storage/storageAccounts'

        do 
        {
            $StorageAccountName = Read-Host "Please Enter a name for the new Storage Account"
            $ResourceNameCheck = Invoke-ResourceNameAvailability -ResourceName $StorageAccountName -ResourceType $ResourceType -SubscriptionID $SubscriptionID -ResourceKind $ResourceKind
            if (($ResourceNameCheck).nameAvailable -eq $true)
            {
                $ResourceNameAvailability = $true
            }
            else 
            {
                Write-Warning -message $ResourceNameCheck.message
            }
            
        } 
        until ($ResourceNameAvailability -eq $true)

        $DestinationStorageAccount = New-AzStorageAccount -Name $StorageAccountName -ResourceGroupName $StorageAccountResourceGroup.ResourceGroupName -Location $Location -SkuName Standard_LRS -Kind Storage -Verbose

        # Create Storage Account Container
        $ResourceNameAvailability = $false
        $StorageAccountContainerNameRegex = '^[a-z0-9]+(-[a-z0-9]+)*$'

        do 
        {
            $StorageAccountContainerName = Read-Host "Please Choose a name for the Storage Account Container"
            if ($StorageAccountContainerName -notmatch $StorageAccountContainerNameRegex)
            {
                Write-Warning -Message 'Container names must be lowercase letters, numbers, and hyphens. It must Start with lowercase letter or number and cannot use consecutive hyphens'
            }
            if (($StorageAccountContainerName.Length -lt 3) -or ($StorageAccountContainerName.Length -gt 63))
            {
                Write-Warning -Message 'Container names must be between 3 and 63 characters'
            }
            elseif (($StorageAccountContainerName -match $StorageAccountContainerNameRegex) -and ($StorageAccountContainerName.Length -ge 3) -and ($StorageAccountContainerName.Length -le 63))
            {
                $ResourceNameAvailability = $true
            }
        } 
        until ($ResourceNameAvailability -eq $true)

        $DestinationStorageAccountContainer = New-AzureStorageContainer -Context $DestinationStorageAccount.Context -Name $StorageAccountContainerName -Permission Blob -Verbose

    }
    else 
    {
        # Proceed with existing Storage Account
        $DestinationStorageAccount = Get-AzStorageAccount | Where-Object {$_.StorageAccountName -eq $DestinationStorageAccountName} | Select-Object -Property *

        $DestinationStorageAccountContainers = @()
        $DestinationStorageAccountContainers += 'New'
        $DestinationStorageAccountContainers += (Get-AzureStorageContainer -Context $DestinationStorageAccount.Context | Where-Object {$_.PublicAccess -eq 'Blob'}).Name
        $DestinationStorageAccountContainer = $DestinationStorageAccountContainers | Out-GridView -Title "Please Select the storage account container." -PassThru
    }

    If ($DestinationStorageAccountContainer -eq 'New')
    {
        # Create Storage Account Container
        $ResourceNameAvailability = $false
        $StorageAccountContainerNameRegex = '^[a-z0-9]+(-[a-z0-9]+)*$'

        do 
        {
            $StorageAccountContainerName = Read-Host "Please Choose a name for the Storage Account Container"
            if ($StorageAccountContainerName -notmatch $StorageAccountContainerNameRegex)
            {
                Write-Warning -Message 'Container names must be lowercase letters, numbers, and hyphens. It must Start with lowercase letter or number and cannot use consecutive hyphens'
            }
            if (($StorageAccountContainerName.Length -lt 3) -or ($StorageAccountContainerName.Length -gt 63))
            {
                Write-Warning -Message 'Container names must be between 3 and 63 characters'
            }
            elseif (($StorageAccountContainerName -match $StorageAccountContainerNameRegex) -and ($StorageAccountContainerName.Length -ge 3) -and ($StorageAccountContainerName.Length -le 63))
            {
                $ResourceNameAvailability = $true
            }
        } 
        until ($ResourceNameAvailability -eq $true)

        $DestinationStorageAccountContainer = New-AzureStorageContainer -Context $DestinationStorageAccount.Context -Name $StorageAccountContainerName -Permission Blob -Verbose
    }
    else
    {
        $DestinationStorageAccountContainer = Get-AzureStorageContainer -Context $DestinationStorageAccount.Context -Name $DestinationStorageAccountContainer
    }

    return $DestinationStorageAccountContainer,$DestinationStorageAccount
}

#region Connect to Azure
$Environments = Get-AzEnvironment
$Environment = $Environments | Out-GridView -Title "Please Select an Azure Enviornment." -PassThru

try
{
    Connect-AzAccount -Environment $($Environment.Name) -ErrorAction 'Stop'
}
catch
{
    Write-Error -Message $_.Exception
    break
}
#endregion

#region Subscription Selection
$VirtualMachineSubscriptions = Get-AzSubscription | Where-Object {$_.State -eq 'Enabled'}
if ($VirtualMachineSubscriptions.Count -gt '1')
{
    $VirtualMachineSubscription = $VirtualMachineSubscriptions | Out-GridView -Title "Please Select the Subscription containing your Virtual Machines." -PassThru
    Set-AzContext $Subscription
}
#endregion

#region Location Selection
$Locations = Get-AzLocation
$Location = ($Locations | Out-GridView -Title "Please Select a location for your New or Existing Resources." -PassThru).Location
#endregion

#region Get VM Resource Group
$VirtualMachineResourceGroups = Get-AzResourceGroup | Select-Object ResourceGroupName
$VirtualMachineResourceGroup = $VirtualMachineResourceGroups | Out-GridView -Title "Please Select the Resource Group containing your Virtual Machines." -PassThru
$VirtualMachineResourceGroup = Get-AzResourceGroup -Name $VirtualMachineResourceGroup.ResourceGroupName
#endregion

#region Get VMs
$VirtualMachines = @()
$VirtualMachines += 'All'
$VirtualMachines += (Get-AzVM -ResourceGroupName $VirtualMachineResourceGroup.ResourceGroupName).Name
$SelectedVirtualMachines = $VirtualMachines | Out-GridView -Title "Please Select the Resource Group containing your Virtual Machines." -PassThru

if ($SelectedVirtualMachines -eq 'All')
{
    $VirtualMachines = Get-AzVM -ResourceGroupName $VirtualMachineResourceGroup.ResourceGroupName
}
else
{
    $VirtualMachines = @()
    foreach ($SelectedVirtualMachine in $SelectedVirtualMachines)
    {
        $VirtualMachines += Get-AzVM -ResourceGroupName $VirtualMachineResourceGroup.ResourceGroupName -Name $SelectedVirtualMachine
    }
}
#endregion

#region Get Image Storage Account Details
$StorageAccount = Invoke-StorageAccountSelectionCreation -Location $Location
$StorageAccountKey = Get-AzStorageAccountKey -ResourceGroupName $StorageAccount.ResourceGroupName -AccountName $StorageAccount.StorageAccountName
$DestinationContext = New-AzureStorageContext –storageAccountName $StorageAccount.StorageAccountName -StorageAccountKey ($StorageAccountKey).Value[0]
#endregion

#region Begin Snapshot Creation
foreach ($VirtualMachine in $VirtualMachines)
{
    $SnapShots = @()

    # Identify OS Type
    if ($VirtualMachine.OSProfile.LinuxConfiguration)
    {
        $VirtualMachineOSType = 'Linux'
    }
    else
    {   
        $VirtualMachineOSType = 'Windows'
    }

    Write-Host "Virtual Machine Operating System is $VirtualMachineOSType" -ForegroundColor Green
    Write-Host "Preparing Virtual Machine $($VirtualMachine.Name) Snapshot" -ForegroundColor White

    $VirtualMachineStorageProfile = $VirtualMachine.StorageProfile

    # Get VM PowerState and power off if running
    if ((Get-AzVM -ResourceGroupName $VirtualMachine.ResourceGroupName -Name $VirtualMachine.Name -Status).Statuses.DisplayStatus[1] -eq 'VM running')
    {
        $VirtualMachinePowerState = 'Running'
        Write-Host "Virtual Machine $($VirtualMachine.Name) is currently running." -ForegroundColor Yellow
        Write-Host "Powering off the virtual Machine before taking the Snapshot." -ForegroundColor Yellow
        Stop-AzVM -Name $VirtualMachine.Name -ResourceGroupName $VirtualMachine.ResourceGroupName -Force -Verbose
    }

    #region OS Disk Snapshot
    Write-Host "Creating OS Disk Snapshot Config for Virtual Machine $($VirtualMachine.Name)" -ForegroundColor White
    $OSDiskSnapshotConfig = New-AzSnapshotConfig -SourceUri $VirtualMachineStorageProfile.OsDisk.ManagedDisk.id `
        -CreateOption Copy `
        -Location $VirtualMachine.Location `
        -OsType $VirtualMachineOSType `
        -NetworkAccessPolicy AllowAll `
        -Verbose

    $SnapshotNameOsDisk = "$($VirtualMachineStorageProfile.OsDisk.Name)_OSDisk"

    Write-Host "Taking OS Disk Snapshot for Virtual Machine $($VirtualMachine.Name)" -ForegroundColor Green
    $SnapShots += New-AzSnapshot -ResourceGroupName $VirtualMachine.ResourceGroupName -SnapshotName $SnapshotNameOsDisk -Snapshot $OSDiskSnapshotConfig -Verbose -ErrorAction Stop
    #endregion

    #region Data Disk Snapshots
    if ($VirtualMachineStorageProfile.DataDisks)
    {
        [Int]$DataDiskNumber = '0'
        Write-Host "Virtual Machine $($VirtualMachine.name) has Data Disks" 
        Write-Host "Snapshots of the data disks will be created"
 
        foreach ($DataDisk in $VirtualMachineStorageProfile.DataDisks) 
        {
            $DataDisk = Get-AzDisk -ResourceGroupName $VirtualMachine.ResourceGroupName -DiskName $DataDisk.Name
 
            Write-Host "Creating Snapshot of Virtual Machine $($VirtualMachine.name) Data Disk $($DataDisk.Name)"
 
            $DataDiskSnapshotConfig = New-AzSnapshotConfig -SourceUri $DataDisk.Id -CreateOption Copy -Location $Location
            $DataDiskSnapshotName = "$($DataDisk.name)_SS$DataDiskNumber"
 
            $SnapShots += New-AzSnapshot -ResourceGroupName $VirtualMachine.ResourceGroupName -SnapshotName $DataDiskSnapshotName -Snapshot $DataDiskSnapshotConfig -ErrorAction Stop
          
            Write-Host "Virtual Machine $($VirtualMachine.Name) Data Disk $($DataDisk.Name) Complete"

            $DataDiskNumber++
        }
    }
    #endregion

    #region Copy Snapshots to Storage Account then remove Snapshots
    [String]$DestinationContainerName = $($StorageAccount.Name)
    $DestinationContainerName = $DestinationContainerName.Trim()

    foreach ($SnapShot in $SnapShots)
    {
        Write-Host "Granting Hot Access to Snapshot $($SnapShot.Name)" -ForegroundColor Green
        $SnapShotSAS = Grant-AzSnapshotAccess -ResourceGroupName $SnapShot.ResourceGroupName -SnapshotName $($SnapShot.Name) -DurationInSecond 3600 -Access Read -Verbose
            
        Write-Host "Copying Snapshot $($SnapShot.Name) to blob storage" -ForegroundColor Green
        $BlobCopy = Start-AzStorageBlobCopy -AbsoluteUri $SnapShotSAS.AccessSAS -DestContainer $DestinationContainerName -DestContext $DestinationContext -DestBlob ("$($VirtualMachine.Name)/" + $($SnapShot.Name) + '.vhd') -Verbose -Force

        Write-Host "Waiting for blob copy to complete..." -ForegroundColor White 
        Get-AzStorageBlobCopyState -Blob $BlobCopy.Name -Container $DestinationContainerName -Context $DestinationContext -WaitForComplete

        Write-Host "Removing Snapshot hot access" -ForegroundColor White
        Revoke-AzSnapshotAccess -ResourceGroupName $SnapShot.ResourceGroupName -SnapshotName $($SnapShot.Name)

        Write-Host "Removing Snapshot $($SnapShot.Name)" -ForegroundColor White
        $SnapShot | Remove-AzSnapshot -Force -Verbose
    }
    #endregion

    # Poweron VM if it was initially running
    if ($VirtualMachinePowerState -eq 'Running')
    {
        Write-Host "Starting Virtual Machine $($VirtualMachine.Name)" -ForegroundColor Green
        Start-AzVM -Name $VirtualMachine.Name -ResourceGroupName $VirtualMachine.ResourceGroupName
    }
}
#endregion