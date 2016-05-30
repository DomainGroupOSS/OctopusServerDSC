# OctopusServerDSC

A DSC resource for installing Octopus Deploy 3.0 server nodes. 

This is the engine behind Domain.com.au's all-singing, all-dancing autoscaling Octopus Deploy setup in AWS. 
When AWS Autoscaling requests a new instance, this code is pulled from S3 onto the new node, and does the install of Octopus Server.
DSC is required because Octopus uses DPAPI to generate certificates, and while AWS's unattended boot doesn't load a profile - so can't use DPAPI - DSC _does_ load a profile, and therefore can.

If you're in a different cloud environment - or running in a data center - your mileage may vary, however an effort has been made to allow overriding of AWS-specific features

### Limitations ###

- Some AWS-specific code can be overridden using the LocalIpAddress and LocalHostName optional parameters, however the Cleanup-Nodes function is not expected to work outside AWS.
- Configuration Drift is not managed in any depth, since this resource was built for an auto-scaling environment in which nodes are short-lived
- We recommend thorough testing before putting this code into your own environment. Obviously.
- This version downloads installation source MSIs from Octopus Deploy's own servers. This means Internet connectivity is required. This is, however, easily modified

### Thanks ###

This resource owes a huge debt of gratitude to the team at Octopus Deploy, and is based loosely on their OctopusDSC tentacle agent resource.

### Example ###

```
==================================================================================================================

configuration MyOctopusServer
{
    Import-DscResource -ModuleName OctopusServerDSC;
    Import-DscResource -ModuleName OctopusDSC;    # OctopusDSC is maintained by the team at Octopus Deploy
    
    node (hostname)
    {
        OctopusServer DeployNode
        {
            Name = $env:computername
            Ensure = "Present"
            DatabaseEndpoint = $dbEndpoint       # SQL Server
            DatabaseName = $dbname
            DatabaseUserName = $DBUserName
            DatabasePassword = $dbpassword
			FileShareLocation = E:\Octopus       # note: HA edition requires a shared location - at Domain we map an NFS drive to E:\
            HostName = $HostName
            LocalIpAddress = $localIp            # optional in AWS, required elsewhere
            LocalHostName = $localHostName       # optional in AWS, required elsewhere
            MasterKey = $MasterKey
            AdminPassword = $AdminPassword
			LicenceBase64 = $licence             # required for new installs. If a DB exists and we're merely joining to it, this is not required 
			Version = "3.0.24.0-x64"
        }  
        
        cTentacleAgent Tentacle  # we also install a tentacle, for management purposes
        {
            Ensure = "Present"
            OctopusServerUrl = "http://$HostName/"
            ApiKey = "API-ABCDEFGHIJKLMNOPQRSTUVWXYZ"
            Environments = "Management"
            Roles = "octopus-server"
            DefaultApplicationDirectory = "C:\Octopus"
            Name = "Tentacle"
        }  
    }
}

MyOctopusServer

Start-DSCConfiguration -verbose -force -wait -path .\MyOctopusServer

==================================================================================================================
```

Octopus Deploy - and especially HA edition - is subject to licencing requirements. We strongly advise contacting Octopus Deploy directly for questions on licencing and limitations, as we cannot provide advice in this area.

However, if you have questions about OctopusServerDSC, contact us via http://tech.domain.com.au/ or send a message to Jason Brown : @cloudyopspoet on twitter, or 'stopthatastronaut' on github

Find out more : http://tech.domain.com.au/2015/09/a-clutch-of-octopodes-moving-to-octopus-deploy-3-0-ha-edition/


### Licence ###

The MIT License (MIT)

Copyright (c) 2016 Domain Group (http://www.domain.com.au/group)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.