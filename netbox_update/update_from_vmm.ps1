####################################
# Edit this variables              # 
####################################
$netbox_srv = "<netbox-server-address>"
$token = "<netbox-api-token>"
$work_dir = "<path-to-work-dir>"

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
# Block of Netbox uri-es           #
####################################
$vm_uri = "$netbox_srv/api/virtualization/virtual-machines/" 
$vm_int_uri = "$netbox_srv/api/virtualization/interfaces/"
$ipaddr_uri = "$netbox_srv/api/ipam/ip-addresses/"
$site_uri = "$netbox_srv/api/dcim/sites/"
$cluster_uri = "$netbox_srv/api/virtualization/clusters/"
$tags_uri = "$netbox_srv/api/extras/tags/"
$vdisks_uri = "$netbox_srv/api/virtualization/virtual-disks/"

#################################### 
# Block of logs                    #
####################################
$tags_log = "$work_dir\tags.txt"
$vm_log = "$work_dir\vms.txt"

####################################
# Block of Functions               #
####################################
# VMs
Function all_vms () {
    $vm_uri = "$vm_uri"+"?limit=2000"
    $request = Invoke-RestMethod -Uri $vm_uri -Headers $Headers
    $global:all_vm_names = $request.results.name
}

Function check-hv-vm ($vm_name) {
    $vm_uri = "$vm_uri"+"?name=$vm_name"+"&cluster_type_id=1"
    $request = Invoke-RestMethod -Uri $vm_uri -Headers $Headers
    if ($request.count -ne 0)
    {
        $global:vh_vm = $vm_name
        $global:vm_id = $request.results.id
    }else
    {
        $global:vh_vm = ''
        $global:vm_id = ''
    }
}

Function update-vm ($vm_name, $vcpus, $Headers, $memory, $description, $vm_tags, $vm_os, $vm_id, $status) {
    $vm_uri = "$vm_uri"+"$vm_id/"
    $jsondata = @{"name"=$vm_name;
            "status"=$status;
            "vcpus"=$vcpus;
            "memory"=$memory;
            "description"=$description;
            }
Invoke-RestMethod -Uri $vm_uri -Headers $Headers -Method PATCH -Body ($jsondata | ConvertTo-Json)
}

Function get-vm-from-vmm ($vh_vm) {
    $global:vm_info = ''
    $global:vm_info = Get-SCVirtualMachine -Name $vh_vm | Foreach-Object {
    $ipv4 = ($_ | Get-SCVirtualNetworkAdapter).ipv4Addresses      
    $_ | Select-Object *,@{N='ipv4Addresses';E={$ipv4}}
    }
    if ($vm_info)
    {
        $global:description = $vm_info.Description
        $global:vm_tags = $vm_info.Tag
        $global:vm_os = $vm_info.OperatingSystem
        $global:vcpus = $vm_info.CPUCount
        $global:memory = $vm_info.Memory
        $global:vm_ips = $vm_info.ipv4Addresses
        $vm_state = $vm_info.Status
        if ($vm_state -eq 'Running') 
        {
            $global:status = "active"
            $global:ipstatus = "active"}
        else 
        {
            if ($state -eq 'PowerOff') 
            {
                $global:status = "offline"
                $global:ipstatus = "reserved"
            }
            else 
            {
                $global:status = "failed"
                $global:ipstatus = "reserved"
            }
        }
    }else
    {
        #!
    }
}

Function decommisioning_vm ($vm_id) {
    $vm_uri = "$vm_uri"+"$vm_id/"
    $jsondata = @{"status"='decommissioning';
            }
Invoke-RestMethod -Uri $vm_uri -Headers $Headers -Method PATCH -Body ($jsondata | ConvertTo-Json)
}

# tag-parser парсим теги с VMM -> get-tag проверяем существует ли такой тег в Netbox

Function tag-parser ($vm_tags) {
    $tags_id = @()
    if ($vm_tags -eq '(none)')
    {
        $global:vm_tag = ''
    } 
    else
    {
        $tags = ($vm_tags).Split(",")
        Foreach ($tag in $tags)
        {
            $tag = $tag.Trim()
            get-tag -tag $tag
            if ($tag_id)
            {
                $tags_id = @($tag_id) + $tags_id
            }
            else
            {
                Add-Content -Path $tags_log "Тег $tag - не найден"
            }
        }
        add-tag-to-vm -tag_id $tags_id -vm_id $vm_id
    }
} 

Function get-tag ($tag) {
    $global:tag_id = ''
    $tag_uri = "$tags_uri"+"?slug=$tag"
    $request = Invoke-RestMethod -Uri $tag_uri -Headers $Headers
    $global:tag_id = $request.results.id
}

Function add-tag-to-vm ($tag_id, $vm_id) {
    $vm_uri = "$vm_uri"+"$vm_id/" 
    $jsondata = @{"tags" = @($tag_id);
                }
    Invoke-RestMethod -Uri $vm_uri -Headers $Headers -Method PATCH -Body ($jsondata | ConvertTo-Json)
}

# Disks 
Function get-disks-from-vmm ($vh_vm) {
    $disks = Get-SCVirtualDiskDrive -VM $vh_vm
    foreach ($hard in $disks)
    {
        $vhd_id = $hard.VirtualHardDiskId
        $vhd_details = Get-SCVirtualHardDisk -ID $vhd_id
        $global:vhd_name = $vhd_details.Name
        $csv = $vhd_details.Directory
        $idx1 = $csv.IndexOf("C:\ClusterStorage") 
        $csv = $csv.Substring($idx1 + 18)
        $idx2 = $csv.IndexOf("\")
        $global:csv = $csv.Substring(0,$idx2)
        $global:vhd_size = $vhd_details.Size / 1073741824
        $global:vhd_max = $vhd_details.MaximumSize / 1073741824
        disk-in-netbox -vh_vm $vh_vm -vhd_name $vhd_name -vhd_size $vhd_size
    }
}

Function disk-in-netbox ($vh_vm, $vhd_name, $vhd_size) {
    $vdisk_id = ''
    $vdisk_uri = $vdisks_uri + "?name=$vhd_name"
    $request = Invoke-RestMethod -Uri $vdisk_uri -Headers $Headers
    $vdisk_id = $request.results.id
    if ($vdisk_id)
    {  # Updating existing virtual disk in netbox
        $vdisk_uri = $vdisks_uri + $vdisk_id + "/"
        $jsondata = @{"virtual_machine"=$vm_id;
            "size"=$vhd_max;}
        Invoke-RestMethod -Uri $vdisk_uri -Headers $Headers -Method PATCH -Body ($jsondata | ConvertTo-Json)
    }else
    {  # Add new virtual disk in netbox
        $vm_uri1 = $vm_uri + "?name=$vh_vm"
        $request = Invoke-RestMethod -Uri $vm_uri1 -Headers $Headers
        $vm_id = $request.results.id
        $jsondata = @{"virtual_machine"=$vm_id;
            "name"=$vhd_name;
            "size"=$vhd_max;}
        Invoke-RestMethod -Uri $vdisks_uri -Headers $Headers -Method POST -Body ($jsondata | ConvertTo-Json)
    }
}

# Network
Function vm-network ($vh_vm, $vm_ips, $vm_id) {
    $interface_number = 0
    foreach ($ipaddress in $vm_ips)
    {
        $interface_number = $interface_number + 1 
        $interface_name = "$vh_vm-int0$interface_number"
        $jsondata = @{"virtual_machine" = $vm_id;
                    "name"=$interface_name;}
        Invoke-RestMethod -Uri "$vm_int_uri" -Headers $Headers -Method POST -Body ($jsondata | ConvertTo-Json)
        if ($interface_number -eq 1) {$primary_ip = 1} else {$primary_ip = 0}
        $ip_id = ''
        $ipaddr_uri = "$ipaddr_uri"+"?address=$ipaddress"
        $request = Invoke-RestMethod -Uri "$ipaddr_uri" -Headers $Headers
        $ip_id = $request.results.id
        if ($ip_id)
        {
            #get interface id
            #update ip address (bind to vm)
            $ipaddress = "$ipaddress"+"/24"
            $ipaddr_uri = "$ipaddr_uri"+"$ip_id/"
            $jsondata = @{
            "status" = $ipstatus;
            "assigned_object_type" = "virtualization.vminterface";
            "assigned_object_id" = $int_id;}
            Invoke-RestMethod -Uri $ipaddr_uri -Headers $Headers -Method PATCH -Body ($jsondata | ConvertTo-Json)
            # set primary ip
            if ($primary_ip -eq 1) 
            { 
                assign-primary-ip -ip_id $ip_id -vm_id $vm_id
            }
        }else
        {
            #get interface id
            get-interface-id -interface_name $interface_name
            #create ip in netbox
            $ipaddress = "$ipaddress"+"/24"
            $jsondata = @{"address" = $ipaddress;
                "status" = "active";
                "assigned_object_type" = "virtualization.vminterface";
                "assigned_object_id" = $int_id;}
            Invoke-RestMethod -Uri $ipaddr_uri -Headers $Headers -Method POST -Body ($jsondata | ConvertTo-Json)
            # set primary ip
            if ($primary_ip -eq 1) 
            { 
                get-ip-id -ipaddress $ipaddress
                assign-primary-ip -ip_id $ip_id -vm_id $vm_id
            }
        }
    }
 }

Function assign-primary-ip ($ip_id, $vm_id){
    $vm_uri = "$vm_uri"+"$vm_id/"
    $jsondata = @{
    "primary_ip" = $ip_id;
    "primary_ip4" = $ip_id;}
    Invoke-RestMethod -Uri $vm_uri -Headers $Headers -Method PATCH -Body ($jsondata | ConvertTo-Json)
 }

Function get-ip-id ($ipaddress) {
    $ipaddr_uri = "$ipaddr_uri"+"?address=$ipaddress"
    $request = Invoke-RestMethod -Uri "$ipaddr_uri" -Headers $Headers
    $global:ip_id = $request.results.id
}

Function get-interface-id ($interface_name) {
    $vm_int_uri = "$vm_int_uri"+"?name=$interface_name"
    $request = Invoke-RestMethod -Uri $vm_int_uri -Headers $Headers
    $global:int_id = $request.results.id
}
# Sites

# Report

####################################
#                                  #
####################################

all_vms
Clear-Content -Path $tags_log
foreach ($vm_name in $all_vm_names)
{
    check-hv-vm -vm_name $vm_name
    if ($vh_vm)
    {
        get-vm-from-vmm -vh_vm $vh_vm
        tag-parser -vm_tags $vm_tags
        if ($vm_info) 
        {
            update-vm -vm_name $vh_vm -vcpus $vcpus -Headers $Headers -memory $memory -description $description -vm_os $vm_os -vm_id $vm_id -status $status
            get-disks-from-vmm -vh_vm $vh_vm
            vm-network -vh_vm $vh_vm -vm_ips $vm_ips -vm_id $vm_id
        }else
        {
            decommisioning_vm -vm_id $vm_id
        }
    }
}

    

