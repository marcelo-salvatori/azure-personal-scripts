function Login
{
    $needLogin = $true
    Try 
    {
        $content = Get-AzContext
        if ($content) 
        {
            $needLogin = ([string]::IsNullOrEmpty($content.Account))
        } 
    } 
    Catch 
    {
        if ($_ -like "*Login-AzAccount to login*") 
        {
            $needLogin = $true
        } 
        else 
        {
            throw
        }
    }

    if ($needLogin)
    {
        Login-AzAccount
    }
}

Login

$subs = Get-AzSubscription | Out-GridView -Title "Select a subscription" -OutputMode Multiple

$date = Get-Date -UFormat "%Y-%m-%d"

$backupsPath = 'C:\Azure Backups\'

$backupsPathExist = Test-Path $backupsPath -PathType Container

if ($backupsPathExist -eq "True"){
	Write-Host "Folder $backupsPath already exists" 
}
else {
	Write-Host "Folder $backupsPath does not exist. Let's create it now..."
	New-Item -ItemType directory -Path $backupsPath
}

foreach ($sub in $subs){

    Select-AzSubscription -Subscription $sub
    
    $subName = $sub.Name

	$subPath = "C:\Azure Backups\$subName"

	$subPathExists = Test-Path $subPath -PathType Container

	if ($subPathExists -eq "True"){
		Write-Host "Folder $subPath already exists" 
	}
	else {
		Write-Host "Folder $subPath does not exist. Let's create it now..."
		New-Item -ItemType directory -Path $subPath
	}

    $filepath = "$subPath\$date-$subName-backups.csv"        

    $vaults = Get-AzRecoveryServicesVault
    $backupedVmList = @()

    foreach ($vault in $vaults){
        
		$vaultName = $vault.name

        Set-AzRecoveryServicesVaultContext -Vault $vault

        $i = 1
    
        ($backedVms = Get-AzRecoveryServicesBackupContainer  -ContainerType "AzureVM" -Status "Registered") > 0

        foreach ($backedVm in $backedVms){
            $backupItem = Get-AzRecoveryServicesBackupItem -Container $backedVm -WorkloadType AzureVM
            $jobLastStatus = $backupItem.LastBackupStatus
            $jobLastRecoveryPoint = $backupItem.LatestRecoveryPoint
            $vmName = $backedVm.FriendlyName.ToUpper()
    
            $ObjectName = Get-AzRecoveryServicesBackupContainer -ContainerType "AzureVM" -FriendlyName $vmName -Status Registered -ErrorAction SilentlyContinue

			if ($ObjectName){
				$ObjectPolicy = Get-AzRecoveryServicesBackupItem  -Container $ObjectName -WorkloadType "AzureVM" -ErrorAction SilentlyContinue
			}

            $statusVm = "Collecting info from " + $vmName

            Write-Progress -Activity "Collecting Information from vault $vaultName in the subscription $subName" -status $statusVm  -percentComplete ($i / $backedVms.Count*100)
                $i ++
            Write-Host -ForegroundColor Green "Collecting info from VM" $vmName

            $backupedVmList += New-Object PSObject -Property @{
                VirtualMachineName = $vmName
                ResourceGroupName = $backedVm.ResourceGroupName
                Status = $backedVm.Status
                VaultName = $vault.Name
                LastBackupStatus = $jobLastStatus
                LastBackupRecoveryPoint = $jobLastRecoveryPoint
                LastBackupDate = $ObjectPolicy.LastBackupTime
                BackupPolicy = $ObjectPolicy.ProtectionPolicyName
            
            }
        }
    }

    $backupedVmList | Select-Object VirtualMachineName,ResourceGroupName,VaultName,Status,LastBackupStatus,LastBackupRecoveryPoint,LastBackupDate,BackupPolicy | `
    Export-Csv -NoTypeInformation $filepath
}