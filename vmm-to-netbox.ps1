####################################
###
### Import VM from VMM to Netbox     
### Dmitriev_BN                      
###
####################################



####################################
# Edit this variables              # 
####################################
$netbox_srv = "https://<your_netbox_server>"
$token = "<your_netbox_api_token>" 


####################################
# Connection headers               #
####################################
$Headers = @{}
$Headers.Add("Authorization", "Token $token") 
$Headers.Add("Content-Type", "application/json")
$Headers.Add("Accept", "application/json")
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls, [Net.SecurityProtocolType]::Tls11, [Net.SecurityProtocolType]::Tls12, [Net.SecurityProtocolType]::Ssl3
[Net.ServicePointManager]::SecurityProtocol = "Tls, Tls11, Tls12, Ssl3"


####################################
# Block of Functions               #
####################################
Function Create_VM ($vmname, $vcpus, $Headers, $vmos, $memory, $description, $site_id, $cluster_id)
    {
    $jsondata = @{"name"=$vmname;
            "status"=$status;
            "site"=$site_id;
            "cluster"=$cluster_id;
            "vcpus"=$vcpus;
            "memory"=$memory;
            "description"=$description;}
Invoke-RestMethod -Uri $vm_uri -Headers $Headers -Method POST -Body ($jsondata | ConvertTo-Json)
    }

Function Create_VM_Net_Interface ($vmname, $interface_name, $Headers)
    {
    Get_Vm_Id -vmname $vmname
    $jsondata = @{"virtual_machine" = $vm_id;
                "name"=$interface_name;}
    Invoke-RestMethod -Uri "$vm_int_uri" -Headers $Headers -Method POST -Body ($jsondata | ConvertTo-Json)
    }

Function Create_Ip_Address  ($interface_name, $ipaddress, $ipaddr_uri, $status, $primary_ip)
    {
    Get_Interface_Id -interface_name $interface_name
    $ipaddress = "$ipaddress"+"/24"
    $jsondata = @{"address" = $ipaddress;
                "status" = "active";
                "assigned_object_type" = "virtualization.vminterface";
                "assigned_object_id" = $int_id;}
    Invoke-RestMethod -Uri $ipaddr_uri -Headers $Headers -Method POST -Body ($jsondata | ConvertTo-Json)
    if ($primary_ip -eq 1) 
        { 
        Assign_Primary_Ip  -ip_id $ip_id -vm_id $vm_id
        }
    }

Function Update_Ip_Address  ($interface_name, $ipaddress, $ipaddr_uri, $status, $primary_ip)
    {
    Get_Interface_Id -interface_name $interface_name
    Get_Ipaddress_Id -ipaddress $ipaddress
    $ipaddress = "$ipaddress"+"/24"
    $ipaddr_uri = "$ipaddr_uri"+"$ip_id/"
    $jsondata = @{
                "status" = $ipstatus;
                "assigned_object_type" = "virtualization.vminterface";
                "assigned_object_id" = $int_id;}
    Invoke-RestMethod -Uri $ipaddr_uri -Headers $Headers -Method PATCH -Body ($jsondata | ConvertTo-Json)
    if ($primary_ip -eq 1) 
        { 
        Assign_Primary_Ip  -ip_id $ip_id -vm_id $vm_id
        }
    }

Function Get_Interface_Id ($interface_name) {
    $vm_int_uri = "$vm_int_uri"+"?name=$interface_name"
    $request = Invoke-RestMethod -Uri $vm_int_uri -Headers $Headers
    $global:int_id = $request.results.id
}

Function Get_Ipaddress_Id ($ipaddress) {
    $ipaddr_uri = "$ipaddr_uri"+"?address=$ipaddress"
    $request = Invoke-RestMethod -Uri "$ipaddr_uri" -Headers $Headers
    $global:ip_id = $request.results.id
}

Function Get_Vm_Id ($vmname) {
    $vm_uri = "$vm_uri"+"?name=$vmname"
    $request = Invoke-RestMethod -Uri $vm_uri -Headers $Headers
    $global:vm_id = $request.results.id
}

Function Get_Site_Id ($site) {
    $siteid_uri = "$site_uri"+"?name=$site"
    $request = Invoke-RestMethod -Uri $siteid_uri -Headers $Headers
    $global:site_id = $request.results.id
    #Create New Site if not exist
    if ($site_id) {} else {
        $jsondata = @{
                "status" = "active";
                "name" = $site;
                "slug" = $site;}
        Invoke-RestMethod -Uri $site_uri -Headers $Headers  -Method POST -Body ($jsondata | ConvertTo-Json)
    }
}

Function Get_Cluster_Id ($cluster) {
    $clusterid_uri = "$cluster_uri"+"?name=$cluster"
    $request = Invoke-RestMethod -Uri $clusterid_uri -Headers $Headers
    $global:cluster_id = $request.results.id
    #Create New Cluster if not exist
    if ($cluster_id) {} else {
        $jsondata = @{
                "status" = "active";
                "type" = 1;
                "name" = $cluster;
                "site" = $site_id;}
        Invoke-RestMethod -Uri $cluster_uri -Headers $Headers -Method POST -Body ($jsondata | ConvertTo-Json)
    }
}

Function Assign_Primary_Ip  ($ip_id, $vm_id)
    {
    $vm_uri = "$vm_uri"+"$vm_id/"
    $jsondata = @{"primary_ip" = $ip_id;
                  "primary_ip4" = $ip_id;}
    Invoke-RestMethod -Uri $vm_uri -Headers $Headers -Method PATCH -Body ($jsondata | ConvertTo-Json)
    }


#################################### 
# Block of Netbox uri-es           #
####################################
$vm_uri = "$netbox_srv/api/virtualization/virtual-machines/" 
$vm_int_uri = "$netbox_srv/api/virtualization/interfaces/"
$ipaddr_uri = "$netbox_srv/api/ipam/ip-addresses/"
$site_uri = "$netbox_srv/api/dcim/sites/"
$cluster_uri = "$netbox_srv/api/virtualization/clusters/"

####################################
# Get Data from VMM                #
####################################

$vms_details = Get-SCVirtualMachine | Foreach-Object {
    $ipv4 = ($_ | Get-SCVirtualNetworkAdapter).ipv4Addresses
    $_ | Select-Object *,@{N='ipv4Addresses';E={$ipv4}}}

foreach ($vm_details in $vms_details){
$vmname = $vm_details.Name
$vmos = $vm_details.OperatingSystem.Name
$ipaddresses = $vm_details.ipv4Addresses
$vcpus = $vm_details.CPUCount
$memory = $vm_details.Memory
$state = $vm_details.VirtualMachineState  
$description = $vm_details.Description
$site = $vm_details.HostGroupPath 
$idx = $site.IndexOf("All Hosts\")
$site = $site.Substring($idx + 10)
$idx = $site.IndexOf("\")
$site = $site.Substring(0,$idx)
$vmhost = $vm_details.VMHost
$cluster_details = Get-SCVMHost -ComputerName $vmhost
$cluster = $cluster_details.HostCluster.ClusterName
# Status converting
if ($state -eq 'Running') {
    $status = "active"
    $ipstatus = "active"}
else {if ($state -eq 'Off') {
    $status = "offline"
    $ipstatus = "reserved"}
      else {
        $status = "failed"
        $ipstatus = "reserved"
      }}

####################################
# Creation/update objects          #
####################################
Get_Site_Id -site $site
Get_Cluster_Id -cluster $cluster

Create_VM -vmname $vmname -vcpus $vcpus -Headers $Headers -vmos $vmos -memory $memory -description $description -site_id $site_id -cluster_id $cluster_id

$interface_number = 0
foreach ($ipaddress in $ipaddresses)
    {
    $interface_number = $interface_number + 1 
    $interface_name = "$vmname-int0$interface_number" 
    Create_VM_Net_Interface -vmname $vmname -interface_name $interface_name -Headers $Headers #
    if ($interface_number -eq 1) {$primary_ip = 1} else {$primary_ip = 0}
    $ip_id = 0
    Get_Ipaddress_Id -ipaddress $ipaddress
    if ($ip_id) {
        Update_Ip_Address -interface_name $interface_name -ipaddress $ipaddress -ipaddr_uri $ipaddr_uri -status $ipstatus -primary_ip $primary_ip -Headers $Headers #
                } else {
        Create_Ip_Address -interface_name $interface_name -ipaddress $ipaddress -ipaddr_uri $ipaddr_uri -status $ipstatus -primary_ip $primary_ip -Headers $Headers #        
                }

    }
}
