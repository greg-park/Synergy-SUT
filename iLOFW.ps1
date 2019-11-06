# Added some comments and checked back in to github
Function CheckQueue {
    $pending = 0
    $ServerInfo = "C:\Users\Gpark\Documents\ServerInfo.csv"
    if ( -not (Test-path -Path $ServerInfo))
    {
        write-host "No file specified or file does not exist."
        return
    }
# Read the CSV Users file
    $tempFile = [IO.Path]::GetTempFileName()
    Get-Content $ServerInfo | Where-Object { ($_ -notlike ",,,,,,,,*") -and ($_ -notlike '"*') -and ( $_ -notlike "#*") -and ($_ -notlike ",,,#*") } > $tempfile   # Skip blank line
    $ListofServers = import-csv $tempfile | Sort-Object NetworkSet

    ForEach ($srvInfo in $ListofServers ) {
        # Make sure iLOs are good
        if ($iLO = Find-HPEiLO $srvInfo.iLO) {

            $username = $srvInfo.iLOUser
            $password =  ConvertTo-SecureString -String $srvInfo.iLOPW -AsPlainText -Force
            $credential = New-Object -TypeName "System.Management.Automation.PSCredential" -ArgumentList $username,$password

            $connection = Connect-HPEiLO -IP $iLO.IP -Credential $credential -DisableCertificateAuthentication
            $info = Get-HPEiLOServerInfo -Connection $connection
            $q = Get-HPEiLOInstallationTaskQueue -Connection $connection

            if ( $q.InstallationTaskQueueInfo) {
            # Check if tasks are complete
                # Write-Host "Number of tasks in queue:",$q.InstallationTaskQueueInfo.Count
                # Write-Host -ForegroundColor Red "Installation queue not empty iLO IP: ", $iLO.IP
                [int] $qDepth = 0
                ForEach ($task in $q.InstallationTaskQueueInfo) {
                    if ( $task.State -eq "Pending") {
                        $pending++        
                        Write-Host "Server: ",$info.ServerName, "iLO Host", $q.Hostname, "Task:",$qDepth," is",  $task.TaskName
                    } 
                    $qDepth++
                }

                if ( $pending -gt 0 ) {
                    # doMM $srvInfo.IP
                    $tc = New-Object -TypeName test_MM

                    if ( $tc.doMM($srvInfo.HostIP)  )  { 
                        Write-Host $ehost.Name, "In maintenance mode.  Good for FW updates"
                        doSut
                        Write-Host "iSUT restrated on all hosts"
                    } else {
                        Write-Host "Host not in maintenance mode"
                    }
                } else { 
                    Write-Host "No pending tasks, all good"
                }
            }
        Disconnect-HPEiLO -Connection $Connection
        } else {
            write-Host $srvInfo.IP,": is NOT ilo"
        }
        Write-Host
    }
}

Function doSut {
    $startSUT   = @'
"sut -start > /dev/null 2>&1 &"
'@
    $stopSUT    = @'
"sut -stop"
'@
    $statSUT    = @'
"sut -status"
'@
    $plink          = "c:\plink\plink.exe"
    $PlinkOptions   = " -batch -pw $Passwd"

    $sshstatus= Get-VMHostService  -VMHost $eHost| where {$psitem.key -eq "tsm-ssh"}
    if ( $sshstatus.Running -eq $False) {
        Get-VMHostService | where {$psitem.key -eq "tsm-ssh"} | Start-VMHostService 
    }

    # Write-Host -Object "Executing Stop sut on $esxHost"
    $output = $plink + " " + $plinkoptions + " " + $root + "@" + $eHost + " " + $stopSUT
    Invoke-Expression $output
#               
    # Write-Host -Object "Executing Start sut on $esxHost"
    $output = $plink + " " + $plinkoptions + " " + $root + "@" + $eHost + " " + $startSUT
    Invoke-Expression $output
    Write-Host -ForegroundColor Cyan "Sleeping for 15s"
    # Start-Sleep -Second 15
    # $output = $plink + " " + $plinkoptions + " " + $root + "@" + $esxHost + " " + $statSUT
    # Invoke-Expression $output
}

class test_MM {
#    [string]$IP
    [int] doMM([string] $IPaddr) {
        $vCenter    = "10.10.209.4"
        $vadm       = "administrator@vsphere.local"
        $vpw        = "HP1nvent!"
        $root       = "root" 
        $Passwd     = "HP1nvent!"
        [int] $MaintMode = 0


        Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false | Out-Null
        New-VICredentialStoreItem -Host $vCenter -Password $vpw -User $vadm -file ".\vicredentials.xml" | Out-Null
        $creds = Get-VICredentialStoreItem -file "vicredentials.xml"
        Connect-VIServer -Server $creds.Host -user $creds.User -password $creds.Password | Out-Null
        $ehost = Get-VMHost -Name $IPaddr

        if ( $ehost.ConnectionState -eq "Maintenance" )  { 
            Write-Host $ehost.Name, "In maintenance mode.  Good for FW updates"
            $MaintMode = 1
        } else {
            $MaintMode = 0
        }
        Disconnect-VIServer -Server $vCenter -Confirm:$False
        
        if ( $MaintMode -gt 0) {
            return 1
        } else {
            return 0
        }
    }
}

## Main and Testing
CheckQueue

# $ServerInfo = "C:\Users\Gpark\Documents\ServerInfo.csv"
# if ( -not (Test-path -Path $ServerInfo))
# {
#     write-host "No file specified or file does not exist."
#     return
# }
# # Read the CSV Users file
# $tempFile = [IO.Path]::GetTempFileName()
# Get-Content $ServerInfo | Where-Object { ($_ -notlike ",,,,,,,,*") -and ($_ -notlike '"*') -and ( $_ -notlike "#*") -and ($_ -notlike ",,,#*") } > $tempfile   # Skip blank line
# $ListofServers = import-csv $tempfile | Sort-Object NetworkSet
# 
# ForEach ($srvInfo in $ListofServers ) {
#     $tc = New-Object -TypeName test_MM
#     if ( $tc.doMM($srvInfo.HostIP) )  { 
#         Write-Host $ehost.Name, "In maintenance mode.  Good for FW updates"
#         # doSut
#         # Write-Host "iSUT restrated on all hosts"
#     } else {
#         Write-Host "Host not in maintenance mode"
#     }
# }