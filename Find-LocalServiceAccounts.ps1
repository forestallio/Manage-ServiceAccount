$MaxThreadCount = 10
$ServiceAccounts = @()

$EnumerateLocalServiceAccounts = {

    param( $hostname )

    $CurrentDomain = $env:USERDOMAIN.ToUpper()

    # https://docs.microsoft.com/en-us/dotnet/api/system.serviceprocess.servicestartmode
    $ServiceStartModes = @{
        0 = "Boot"
        1 = "System"
        2 = "Automatic"
        3 = "Manual"
        4 = "Disabled"
    }

    # https://docs.microsoft.com/en-us/dotnet/api/system.serviceprocess.servicetype
    $ServiceTypes = @{
        1 = "KernelDriver"
        2 = "FileSystemDriver"
        4 = "Adapter"
        8 = "RecognizerDriver"
        16 = "Win32OwnProcess"
        32 = "Win32ShareProcess"
        256 = "InteractiveProcess"
    }

    if ((Test-NetConnection -ComputerName $hostname -Port 445).TcpTestSucceeded){
        try {
            $services = @()
            
            ([ADSI]"WinNT://$($hostname)").Children | 
            ForEach-Object {
                if ($_.schemaclassname -eq "Service"){
                    if ((-not [string]::IsNullOrEmpty($_.ServiceAccountName.value)) -and ($_.ServiceAccountName.value -ilike "*$CurrentDomain*")){
                        $item = [pscustomobject]@{'Computer' = $hostname; 'ServicePath' = $_.Path.value; 'ServiceDisplayName' = $_.DisplayName.value; 'ServiceName' = $_.Name.value; 'ServiceType' = $ServiceTypes[$_.ServiceType.value]; 'ServiceStartType' = $ServiceStartModes[$_.StartType.value]; 'ServiceAccountName'= $_.ServiceAccountName.value}
                        $services += $item
                    }
                }
            }
            return $services
        }
        catch{
            Write-Host -ForegroundColor Red "[!] Failed to enumerate $hostname : $($_.toString())"
            return $null
        }
    }
    else{
        Write-Host -ForegroundColor Red "[!] $hostname port 445 is unreachable"
        return $null
    }        
}


function ProcessCompletedJobs(){

    $jobs = Get-Job -State Completed

    foreach( $job in $jobs ) {
        
        $services = Receive-Job $job
        Remove-Job $job 
        
        if ( $null -ne $services ){
            foreach( $service in $services ){
                $Script:ServiceAccounts += $service
            }
        }
    }
}

Import-Module ActiveDirectory

Write-Host -ForegroundColor Yellow "[+] Retrieving enabled computer list from Domain Controller"
$computers = Get-ADComputer -Filter * -Properties DNSHostName, cn | Where-Object { $_.enabled } 

Write-Host -ForegroundColor Green "[!] Total $($computers.Count) computer found"

$counter = 0
foreach( $computer in $computers ){
    if(-not [string]::IsNullOrEmpty($computer.dnshostname)){
        Start-Job -ScriptBlock $EnumerateLocalServiceAccounts -Name "Enum$($computer.cn)" -ArgumentList $computer.dnshostname | Out-Null
        ++$counter
        Write-Progress -Activity "Enumerating local services from computers" -Status "Enumerating..." -PercentComplete ( $counter * 100 / $computers.Count )
        while ( ( Get-Job -State Running).count -ge $MaxThreadCount ) { Start-Sleep -Seconds 3 }
        ProcessCompletedJobs
    }
}

Write-Progress -Activity "Enumerating local services from computers" -Status "Waiting for jobs to complete..." -PercentComplete 100
Wait-Job -State Running -Timeout 30  | Out-Null
Get-Job -State Running | Stop-Job
ProcessCompletedJobs

$ServiceAccounts | Select-Object -Property Computer,ServicePath, ServiceDisplayName, ServiceName, ServiceType, ServiceStartType, ServiceAccountName | Export-Csv -Path "service_accounts.csv"
