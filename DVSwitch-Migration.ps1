Start-Transcript -Append -Path "$env:USERPROFILE\Documents\DVScopy.log"
$vCenterIP = Read-Host "Enter vCenter IP or Name where the operation needs to be executed"
$myDatacenter = Read-Host "Enter Datacenter Name where the operation needs to be executed"
$Cluster = Read-Host "Enter Cluster Name where the operation needs to be executed"
$NewDVS = Read-Host "Enter a Name for the New DVS"
$NumUplinks = Read-Host "Enter the number of uplink for DVS $NewDVS"
$MyVDSwitch = Read-Host "Enter the Name of Source DVS"
Connect-VIServer $vCenterIP
#Creating new DVS
New-VDSwitch -Name $NewDVS -Location $myDatacenter -Version "5.5.0" -NumUplinkPorts $NumUplinks
#Validation Prompt
$Execute = "No"
While ($Execute -ne "yes")
{
$Execute=Read-Host "Validate and confirm the creation of New DVS.Is the new DVS created as expected?[yes]"
}
#Preparing New PortGroup Configuration
Get-VDSwitch -Name $MyVDSwitch|Get-VDPortgroup | Export-csv -NoTypeInformation $env:USERPROFILE\Documents\ExistingsPGs.csv
$PGname = Import-Csv $env:USERPROFILE\Documents\ExistingsPGs.csv
echo "Name,Vlan,Notes,PortBinding,NumPorts" > $env:USERPROFILE\Documents\NewPGs.csv
ForEach ($PG in $PGname)
{
 $isUplink = $PG.IsUplink
  if($isUplink -eq "False"){
  $Name = $PG.Name
 $Vlan = $PG.VlanConfiguration
 $Name += "-New"
 $Notes = $PG.Notes
 $PortBinding = $PG.PortBinding
 $NumPorts = $PG.NumPorts
 echo $Name","$Vlan","$Notes","$PortBinding","$NumPorts >> $env:USERPROFILE\Documents\NewPGs.csv
  }}
#Validation Prompt
$Execute = "No"
While ($Execute -ne "yes")
{
$Execute=Read-Host "Validate $env:USERPROFILE\Documents\NewPGs.csv and confirm execution[yes]"
}
#Replication the ProtGroup configuration to the new DVS
$NewPGs = Import-Csv $env:USERPROFILE\Documents\NewPGs.csv
ForEach ($PG in $NewPGs)
{
$Name = $PG.Name
$Vlan = $PG.Vlan
$Notes = $PG.Notes
$PortBinding = $PG.PortBinding
$NumPorts = $PG.NumPorts
if($Vlan -ne "")
{
$Vlan = $Vlan.Split(" ")[1]
Write-Host "Creating Portgroup" $Name "with VLAN ID" $Vlan
Get-VDSwitch -Name $NewDVS | New-VDPortgroup -Name $Name -VLanId $Vlan -Notes $Notes -PortBinding $PortBinding -NumPorts $NumPorts
}
else
{
Write-Host "Creating Portgroup" $Name "with No Vlan"
Get-VDSwitch -Name $NewDVS | New-VDPortgroup -Name $Name -Notes $Notes -PortBinding $PortBinding -NumPorts $NumPorts
}
}
#Validation Prompt
$Execute = "No"
While ($Execute -ne "yes")
{
$Execute=Read-Host "Validate and confirm the creation of PortGroups[yes]"
}
#Adding the Host to the new DVS by reading the host list of soruce DVS
$hostnames = Get-VDSwitch -Name $MyVDSwitch|Get-VDPort -Uplink | Select-Object -Unique ProxyHost
$hostnames = $hostnames.ProxyHost
$Execute = "yes"
ForEach ($hostname in $hostnames)
{
    $NicCount = (Get-VDSwitch -Name $MyVDSwitch|Get-VMHostNetworkAdapter -Physical |  Where-Object {$_.VMHost.Name -eq $hostname}).count
    if ($NicCount -lt 2)
    {
        Write-Host -ForegroundColor Red "Found host with one physical Nic only:" $hostname
        $Execute = "no"
    }
     
   Get-VDSwitch -Name $NewDVS|Add-VDSwitchVMHost -VMHost $hostname -Confirm:$false
 }
 
#Validation Prompt
While ($Execute -ne "yes")
{
Write-Host -ForegroundColor Red "We Found host/hosts with one physical Nic only"
Write-Host -ForegroundColor Red "Further execution may cause network outage"
$Execute=Read-Host "Validate and confirm the addtion of Host to $NewDVS.Would you like to proceed further[yes]"
}
#Move Physical Nics. All for host with 1 Nic only and N-1 for host with multiple Nics
ForEach ($hostname in $hostnames)
{
    $NicCount = (Get-VDSwitch -Name $MyVDSwitch|Get-VMHostNetworkAdapter -Physical |  Where-Object {$_.VMHost.Name -eq $hostname}).count
    if ($NicCount -eq 1)
    {    
     $vmhostNetworkAdapter = Get-VDSwitch -Name $MyVDSwitch|Get-VMHostNetworkAdapter -Physical | Where-Object {$_.VMHost.Name -eq $hostname}
     Get-VDSwitch $NewDVS | Add-VDSwitchPhysicalNetworkAdapter -VMHostNetworkAdapter $vmhostNetworkAdapter -Confirm:$false
     }
       
    if ($NicCount -eq 0)
    {
     Write-Host -ForegroundColor Red "No Physical Nic present on $MyVDSwitch for $hostname"
     }
    if ($NicCount -ge 2)
    {
     $Breakpoint =  $NicCount-1 
     $vmhostNetworkAdapters = Get-VDSwitch -Name $MyVDSwitch|Get-VMHostNetworkAdapter -Physical | Where-Object {$_.VMHost.Name -eq $hostname}
        forEach($vmhostNetworkAdapter in $vmhostNetworkAdapters)
        {
          if($Breakpoint -eq 0){break}
          Get-VDSwitch $NewDVS | Add-VDSwitchPhysicalNetworkAdapter -VMHostNetworkAdapter $vmhostNetworkAdapter -Confirm:$false
          $Breakpoint = $Breakpoint -1            
        }
    }
 }
#Validation Prompt
$Execute = "no"
While ($Execute -ne "yes")
{
Write-Host -ForegroundColor Red "Moving VMs from one Portgroup to another will lead to a brief network outage"
$Execute=Read-Host "Validate and confirm the Physical Nic placement for Hosts on $NewDVS.Would you like to proceed further with VM placement[yes]"
}
$PGname = Import-Csv $env:USERPROFILE\Documents\ExistingsPGs.csv
#Virtual Machine placement
ForEach ($PG in $PGname)
{
$isUplink = $PG.IsUplink
 if($isUplink -eq "False")
 {
    $OldNetwork = $PG.Name
    $NewNetwork = $OldNetwork+"-New"
    Get-Cluster $Cluster |Get-VM |Get-NetworkAdapter |Where {$_.NetworkName -eq $OldNetwork } |Set-NetworkAdapter -NetworkName $NewNetwork -Confirm:$false
    }
}
#Validation Prompt
$Execute = "no"
While ($Execute -ne "yes")
{
$Execute=Read-Host "Validate and confirm the Virtual Machine placement on $NewDVS.Would you like to proceed further[yes]"
}
#Move last Physical Nic from the hosts
ForEach ($hostname in $hostnames)
{
    $NicCount = (Get-VDSwitch -Name $MyVDSwitch|Get-VMHostNetworkAdapter -Physical |  Where-Object {$_.VMHost.Name -eq $hostname}).count
    if ($NicCount -eq 1)
    {    
     $vmhostNetworkAdapter = Get-VDSwitch -Name $MyVDSwitch|Get-VMHostNetworkAdapter -Physical | Where-Object {$_.VMHost.Name -eq $hostname}
     Get-VDSwitch $NewDVS | Add-VDSwitchPhysicalNetworkAdapter -VMHostNetworkAdapter $vmhostNetworkAdapter -Confirm:$false
     }
     if ($NicCount -eq 0)
    {
     Write-Host -ForegroundColor Green "No Physical Nic present on $MyVDSwitch for $hostname"
     }
    if ($NicCount -ge 2)
    {
       Write-Host -ForegroundColor Red "Found more than 1 Physical Nic present on $hostname for $MyVDSwitch. This is not expected. review the previous errors and apply manual fix as appropiate"
    }
 }
Disconnect-viserver -confirm:$false
Stop-Transcript
