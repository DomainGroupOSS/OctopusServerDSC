Describe "Repo testing" {
    Context "Checking Repo integrity" {   
         It "Does not include anything that looks like an Octopus API key" {
            # Octopus API keys are 31 chars and start with API-
            $ok = $true
            $badfiles = @()
            $regex = "\bAPI-\w{27}\b" 
            gci -recurse -File -Exclude @("*.zip", "*.msi") | % {
                $match = Select-String -Path $_.FullName -Pattern $regex -CaseSensitive 
                if($match -ne $null)
                {
                    $ok = $false
                    $outmatch = Format-KeyError "$match"
                    Write-Warning "`tOctopus API Key Warning: $outmatch"
                } 
            }
            $ok | Should Be $true 
        }

        It "Doesn't contain anything that looks like an AWS Key or secret" {
            $ok = $true
            $badfiles = @()

            $regex = "\bAK([A-Z0-9]{18})\b" # exactly 20 alphanumeric chars with a word boundary either side, starts with AK
            $secretregex = "\b([A-Za-z0-9/+=]{40})\b"  # exactly 40 base64 chars with a word boundary either side

            gci -recurse -File -Exclude @("*.zip", "*.msi") | % {
                $keymatch = Select-String -Path $_.FullName -Pattern $regex -CaseSensitive
                if($keymatch -ne $null)
                {
                    $ok = $false
                    $outmatch = Format-KeyError "$keymatch"
                    Write-Warning "`tAWS API Key Warning: $outmatch"
                }
                $keymatch = $null
                $secretmatch = Select-String -Path $_.FullName -Pattern $secretregex -CaseSensitive
                if($secretmatch -ne $null)
                {
                    $ok = $false
                    $outmatch = Format-KeyError "$secretmatch"
                    Write-Warning "`tAWS Secret Key Warning: $outmatch" 
                }
                $secretmatch = $null
            }
            $ok | Should Be $true 
        }
    }    
}

Describe "Resource Testing" {   # basic skeleton DSC testing
    Copy-item .\OctopusServerDSC\DSCResources\OctopusServer\OctopusServer.psm1 $env:tmp\OctopusServer.ps1 -Force
    Mock Export-ModuleMember {return $true}  # if you're dot-sourcing the resource as a .ps1, you can't have export-modulemember
    . $env:tmp\OctopusServer.ps1

    $splat = @{  # we will reuse parameters, so splatting is the way to go
                "Ensure" = "Present"; 
                "Name" = "pester-test";
              }

    Context "Get-TargetResource" {    
        It "Should return a hashtable" {            
            (Get-TargetResource @splat).GetType() -as [string] | Should Be 'hashtable'
        } 
    }

    Context "Test-TargetResource" {
        It "returns true or false" {
            (Test-TargetResource @splat).GetType() -as [string] | Should Be 'bool'
        }
    }    
   
    Remove-item $env:tmp\OctopusServer.ps1 -Force
}