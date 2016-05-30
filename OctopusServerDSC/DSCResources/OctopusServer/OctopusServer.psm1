# cOctopusServer is really only here to get past the logged-on profile problem with DPAPI

# Protip: If standing up a new cluster, start with a size of 1. 
# Log in, get the master key, add that to the template, upsize the cluster
# And delete the Admin account you set in CloudFormation!

Function Get-TargetResource
{
    param
    ( 
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        $Name,
        [ValidateSet("Present", "Absent")]
        $Ensure,
        $DatabaseEndpoint,
        $DatabaseName,
        $DatabaseUserName,
        $DatabasePassword,
		$FileShareLocation = "E:\Octopus",
        $HostName,
        $LocalIPAddress,
        $LocalHostName,
        $MasterKey,
        $AdminPassword,
        $LicenceBase64,
        $Version = '3.0.24.0-x64'
     )

     # only a basic subset is implemented here, because we do minimal drift management

     if(Get-Service | ? { $_.Name -eq "OctopusDeploy" }) # is installed, get installed params
     {
        $getTargetResourceResult = @{
                                        Name = $Name;
                                        DatabaseEndpoint = $DatabaseEndpoint;
                                        Ensure = "Present";
                                        HostName = $HostName;
                                    }
     }
     else
     {
        $getTargetResourceResult = @{
                                        Name = $Name; 
                                        DatabaseEndpoint = $DatabaseEndpoint;
                                        Ensure = "Absent";
                                        HostName = $HostName;
                                    }
     }    
    return $getTargetResourceResult
}

Function Set-TargetResource
{

    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        $Name,
        [ValidateSet("Present", "Absent")]
        $Ensure,
        $DatabaseEndpoint,
        $DatabaseName,
        $DatabaseUserName,
        $DatabasePassword,
		$FileShareLocation = "E:\Octopus",
        $HostName,
        $LocalIPAddress,
        $LocalHostName,
        $MasterKey,
        $AdminPassword,
        $LicenceBase64,
        $Version = '3.0.24.0-x64'
    )

    Write-Verbose "Creating a New Octopus instance with parameters:"
    Write-Verbose "DatabaseEndpoint : $DatabaseEndpoint"
    Write-Verbose "DatabaseUserName : $DatabaseUserName"
    Write-Verbose "DatabasePassword : $DatabasePassword"
    Write-Verbose "HostName : $HostName"
    Write-Verbose "LocalIpAddress : $LocalIPAddress"
    Write-Verbose "LocalHostName : $LocalHostName"
    Write-Verbose "MasterKey : $MasterKey"

    Write-Verbose "My path is ${env:path}"

    $computername = $env:computername
    if(!$LocalIPAddress)
    {
        $LocalIPAddress = irm http://169.254.169.254/latest/meta-data/local-ipv4 # AWS metadata endpoint. change for Azure
    }

    if(!$LocalHostName)
    {
        $LocalHostName = irm http://169.254.169.254/latest/meta-data/local-hostname
    }

    $localHostName = $LocalHostName.Replace(" ", ".") # AWS quirk puts a space where we don't want one

	if(!(Test-Path "c:\dom\Octopus3.0"))
	{
		New-Item -path "c:\dom\Octopus3.0" -itemtype directory -force
	}
	
	# get the requested binary. At Domain, we access this via S3, to minimise external dependencies
	iwr "https://download.octopusdeploy.com/octopus/Octopus.$Version.msi" -outfile "C:\dom\Octopus3.0\Octopus.$Version.msi"
	
    # install binaries
    Write-verbose "Performing Octopus Binary install, quiet mode"
    Start-Process  "msiexec" "/i C:\dom\Octopus3.0\Octopus.$Version.msi /quiet" -wait

    #have a little sleepy
    Start-Sleep -Seconds 2

    Write-Verbose "Pushing location"
    Push-Location "c:\Program Files\Octopus Deploy\Octopus"
    Write-Verbose "Working Path is now $pwd"

    $oc = ".\Octopus.Server.exe"
    
    $hostName = $env:computername

    $connString = "Data Source=$DatabaseEndpoint;Initial Catalog=$databasename;Integrated Security=False;User ID=$databaseUserName;Password=$DatabasePassword"

    if(Test-Database $connString)
    {
        Write-Verbose "Database exists, registering against existing Octopus DB instance"
        Invoke-AndAssert    { & $oc create-instance --instance OctopusServer --config $FileShareLocation\OctopusServer-$hostName.config --console }
        Invoke-AndAssert    { & $oc configure --instance OctopusServer --home "$FileShareLocation" --storageConnectionString "$connString" --webForceSSL False --webListenPrefixes "http://localhost:80/,http://127.0.0.1:80/,http://$localIPAddress/,http://$HostName/,http://$localHostName/" --commsListenPort 10943 --serverNodeName $computername --masterKey $MasterKey --console }
        Invoke-AndAssert    { & $oc service --instance OctopusServer --install --console }
        Invoke-AndAssert    { & $oc service --instance OctopusServer --stop --console }
        Invoke-AndAssert    { & $oc service --instance OctopusServer --start --console }
    }
    else
    {
        # Here we stand up the new DB
        Write-Verbose "Database does not exist, creating a new OctopusInstance"
        Invoke-AndAssert    { & $oc create-instance --instance OctopusServer --config $FileShareLocation\OctopusServer-$HostName.config --console }
        Invoke-AndAssert    { & $oc configure --instance OctopusServer --home "$FileShareLocation" --storageConnectionString "$connString" --upgradeCheck True --upgradeCheckWithStatistics True --webAuthenticationMode "UsernamePassword" --webForceSSL "False" --webListenPrefixes "http://localhost:80/,http://127.0.0.1:80/,http://$localIPAddress/,http://$HostName/,http://$localHostName/" --commsListenPort 10943 --console }
        Invoke-AndAssert    { & $oc database --instance OctopusServer --create --console }
        Invoke-AndAssert    { & $oc service --instance OctopusServer --stop }
        Invoke-AndAssert    { & $oc admin --instance OctopusServer --userName Administrator --password "$AdminPassword" }
        Invoke-AndAssert    { & $oc licence --instance OctopusServer --licenceBase64 "$licenceBase64" }
        Invoke-AndAssert    { & $oc service --instance OctopusServer --install --reconfigure --start }
     }
     # clean up the OctopusServerNode database

     Write-Verbose "Cleaning up dbo.OctopusServerNode after a one minute pause"
     Start-Sleep -Seconds 60
	 
	 # Cleanup-Nodes is needed for AWS Autoscaling environments and will not work correctly outside that configuration.
	 # however it should fail quietly
     try
     {
        CleanUp-Nodes -connectionstring $connString
     }
     Catch
     {
        Write-Verbose "Error caught in Cleanup-Nodes"
     }

     Write-Verbose "Octopus Configuration finishing "
}

Function Test-TargetResource
{
    param
    (    
        [ValidateSet("Present", "Absent")]
        $Ensure,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        $Name,
        $DatabaseEndpoint,
        $DatabaseName,
        $DatabaseUserName,
        $DatabasePassword,
		$FileShareLocation = "E:\Octopus",
        $HostName,
        $LocalIPAddress,
        $LocalHostName,
        $MasterKey,
        $AdminPassword,
        $LicenceBase64,
        $Version='3.0.24.0-x64'
    )

    # basically, is Octopus Deploy installed?
    # TODO: validate settings and re-run config
    if(Get-Service | ? { $_.Name -eq "OctopusDeploy" })
    {
        return $true
    }
    else
    {
        return $false
    }
}

function Invoke-AndAssert {  # taken wholesale from OctopusDSC
    param ($block) 
  
    & $block | Write-Verbose
    if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne $null) 
    {
        throw "Command returned exit code $LASTEXITCODE"
    }
}

Function Test-Database
{
    [CmdletBinding()]
    param($connString)
    $oConn = New-Object System.Data.SqlClient.SqlConnection
    $oConn.ConnectionString = $connString
    $dbexists = $true
    try
    {
        $oConn.Open()
        Write-Verbose "DB Connection successful"
    }
    catch
    {
        $dbexists = $false
        Write-Verbose "Database Not Found"
    }
    return $dbexists
}

# from nodes.ps1: octopus database cleanup steps

Function Get-Connection
{
    param($ConnectionString)
    $conn = new-object System.Data.SqlClient.SqlConnection
    $conn.ConnectionString = $connectionstring
    $conn.Open()
    return $conn
}

Function Execute-NonQuery
{
    param($sql, $connectionstring)
    $query = New-Object System.Data.SqlClient.SqlCommand
    $query.Connection = Get-Connection -connectionstring $connectionstring
    $query.commandtext = $sql
    $query.ExecuteNonQuery()
}

Function CleanUp-Nodes # required in autoscaling environments to ensure we don't breach licence limits
{
    param($ConnectionString)
    $machines = Get-machines # finds current machines in environment
    if($machines.count -gt 0)
    {
        $nodelist = $machines -join "','"
        if($nodelist.length -gt 3) {
            $sql = "DELETE dbo.OctopusServerNode WHERE ID NOT IN ('$nodelist')"
            Execute-NonQuery -sql $sql -connectionstring $ConnectionString    # Direct access to the DB is not officially condoned.
        }
    }
}

Function Get-Machines
{
    $nametags = @()
    $instanceID = irm http://169.254.169.254/latest/meta-data/instance-id
    $az = (irm http://169.254.169.254/latest/meta-data/placement/availability-zone)
    $region = $az.substring(0, $az.length-1)
    Write-Verbose "detected region $region"
    $scalingGroup = Get-ASAutoScalingGroup -region $region | ? { $_.instances | ? {$_.instanceID -eq $instanceID}  }
    $scalingGroup.Instances | select -ExpandProperty instanceId | % {
        $nodename = (Get-NameTag -instanceID $_ -region $region)
        $nameTags += $nodename
        Write-Verbose "Found instanceID $_ ($nodename)"
    }
    return $nametags
}

Function Get-NameTag
{
    [CmdletBinding()]
    param($instanceId,$region)
    Write-Verbose "Checking Instance $instanceID"
    $ins = Get-EC2Instance $instanceID -region $region
    return ($ins | select -expand runninginstance | select -expand Tags | ? {$_.key -eq "Name"} | Select -expand Value )
}

Export-ModuleMember -Function *-TargetResource