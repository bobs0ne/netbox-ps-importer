### Block of editable variables
# $netbox_srv - netbox server address
# $token - netbox API token
# $path_to_csv - path to csv file. Csv example:
#        site;cluster;server
#        <Site_Name>;<Cluster_Name>;<Server_Name>
###
$netbox_srv = "https://<netbox_address>"
$token = "<netbox_token>"
$path_to_csv = "<path_to_csv>" 

# Connection headers
$Headers = @{}
$Headers.Add("Authorization", "Token $token") 
$Headers.Add("Content-Type", "application/json")
$Headers.Add("Accept", "application/json")

# Parsing CSV
Import-Csv $path_to_csv -Delimiter ";" | ForEach-Object {
$site=$_.site
$cluster=$_.cluster
$server=$_.server

# Set uri-s
$vm_uri = "$netbox_srv/api/virtualization/virtual-machines/" # 
$site_uri = "$netbox_srv/api/dcim/sites/?name=$site"
$cluster_uri = "$netbox_srv/api/virtualization/clusters/?name=$cluster"

# Get Site ID
$site_request = Invoke-RestMethod -Uri $site_uri -Headers $Headers
$site_id = $site_request.results.id
# Get Cluster ID
$cluster_request = Invoke-RestMethod -Uri $cluster_uri -Headers $Headers
$cluster_id = $cluster_request.results.id

# Get VMs from Hyper-V
$vms = Get-VM  -ComputerName $server  | Select-Object *
foreach ($vm in $vms){
$vmname = $vm.Name
$state = $vm.State
$vcpus = $vm.ProcessorCount
$memory = $vm.MemoryStartup / (1024*1024)
$description = $vm.Notes
$idx = $description.IndexOf("#CLUSTER")
$description = $description.Substring(0,$idx)
$description

# Status convert
if ($state -eq 'Running') {$status = "active"}
else {
    if ($state -eq 'Off') {$status = "offline"}
    else {$status = "failed"}
     }

# Create json for object
$jsondata = @{"name"=$vm.Name;
            "status"=$status;
            "site"=$site_id;
            "cluster"=$cluster_id;
            "vcpus"=$vm.ProcessorCount;
            "memory"=$memory;
            "description"=$vm.Notes;
           }

Invoke-RestMethod -Uri $vm_uri -Headers $Headers -Method POST -Body ($jsondata | ConvertTo-Json)
    }
}

