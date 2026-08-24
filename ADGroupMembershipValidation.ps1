#Requires -Modules ActiveDirectory

<#
.SYNOPSIS
    Multi-Domain AD Group Membership Audit

.DESCRIPTION
    Reads EmployeeIDs from a CSV file and validates membership across
    multiple Active Directory groups located in multiple domains.

.NOTES
    Author  : Saeed Rather
    Version : 2.0.0
    Updated : 08/24/2026
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "==========================================" -ForegroundColor Green
Write-Host "MULTI DOMAIN AD GROUP AUDIT SCRIPT" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green

Import-Module ActiveDirectory

#=========================================================================
# CONFIGURATION
#=========================================================================

# Change this if your AD uses a different attribute name.
$EmployeeIDAttribute = "EmployeeID"

#=========================================================================
# FILE PATHS
#=========================================================================

$ScriptPath   = $MyInvocation.MyCommand.Path
$ScriptFolder = Split-Path -Parent $ScriptPath

$InputFilePath  = Join-Path $ScriptFolder "ip_GetADGroupMember.csv"
$GroupsFilePath = Join-Path $ScriptFolder "ip_Groups.csv"

$OutputFilePath = Join-Path `
    $ScriptFolder `
    ("op_GetADGroupMember_{0}.csv" -f (Get-Date -Format "MM-dd-yyyy_HHmmss"))

#=========================================================================
# VALIDATE FILES
#=========================================================================

if (-not (Test-Path $InputFilePath))
{
    Write-Host "Input user file not found: $InputFilePath" -ForegroundColor Red
    return
}

if (-not (Test-Path $GroupsFilePath))
{
    Write-Host "Input group file not found: $GroupsFilePath" -ForegroundColor Red
    return
}

$InputUsers = Import-Csv $InputFilePath

if (-not $InputUsers)
{
    Write-Host "User input file is empty." -ForegroundColor Red
    return
}

if (-not ($InputUsers[0].PSObject.Properties.Name -contains "EmployeeID"))
{
    Write-Host "Input CSV must contain column: EmployeeID" -ForegroundColor Red
    return
}

$TargetGroups = Import-Csv $GroupsFilePath

if (-not $TargetGroups)
{
    Write-Host "Group input file is empty." -ForegroundColor Red
    return
}

foreach ($RequiredColumn in @('GroupName', 'GroupDomain'))
{
    if (-not ($TargetGroups[0].PSObject.Properties.Name -contains $RequiredColumn))
    {
        Write-Host "Group CSV missing column: $RequiredColumn" -ForegroundColor Red
        return
    }
}

$Domains = $TargetGroups |
    Select-Object -ExpandProperty GroupDomain |
    ForEach-Object { $_.Trim() } |
    Sort-Object -Unique

Write-Host ""
Write-Host "Users Loaded    : $($InputUsers.Count)" -ForegroundColor Yellow
Write-Host "Groups Loaded   : $($TargetGroups.Count)" -ForegroundColor Yellow
Write-Host "Domains Loaded  : $($Domains.Count)" -ForegroundColor Yellow

#=========================================================================
# CACHE GROUP MEMBERS
#=========================================================================

Write-Host ""
Write-Host "Caching group memberships..." -ForegroundColor Yellow

$GroupMembers = @{}

foreach ($GroupEntry in $TargetGroups)
{
    $GroupName    = "$($GroupEntry.GroupName)".Trim()
    $DomainServer = "$($GroupEntry.GroupDomain)".Trim()

    $GroupKey = "$DomainServer|$GroupName"

    try
    {
        Write-Host "Loading [$DomainServer] $GroupName..." -ForegroundColor Cyan

        $Group = Get-ADGroup `
            -Identity $GroupName `
            -Server $DomainServer `
            -Properties Member

        $MemberHash = @{}

        foreach ($MemberDN in $Group.Member)
        {
            if ($MemberDN)
            {
                $MemberHash[$MemberDN.ToUpper()] = $true
            }
        }

        $GroupMembers[$GroupKey] = $MemberHash

        Write-Host "$GroupName : $($MemberHash.Count) members cached" -ForegroundColor Green
    }
    catch
    {
        Write-Warning "Failed loading group [$DomainServer] $GroupName"
        Write-Warning $_.Exception.Message

        $GroupMembers[$GroupKey] = @{}
    }
}

#=========================================================================
# USER LOOKUP CACHE
#=========================================================================

Write-Host ""
Write-Host "Building user cache..." -ForegroundColor Yellow

$UserLookupCache = @{}

$UniqueEmployeeIDs = $InputUsers |
    Select-Object -ExpandProperty EmployeeID |
    ForEach-Object { "$_".Trim() } |
    Where-Object { $_ } |
    Sort-Object -Unique

function New-EmployeeIDLDAPFilter
{
    param(
        [string[]]$EmployeeIDs,
        [string]$AttributeName
    )

    $Parts = foreach ($ID in $EmployeeIDs)
    {
        "($AttributeName=$ID)"
    }

    "(|" + ($Parts -join '') + ")"
}

$BatchSize = 100

foreach ($DomainServer in $Domains)
{
    Write-Host ""
    Write-Host "Searching users in $DomainServer..." -ForegroundColor Yellow

    for ($i = 0; $i -lt $UniqueEmployeeIDs.Count; $i += $BatchSize)
    {
        $EndIndex = $i + $BatchSize - 1

        if ($EndIndex -ge $UniqueEmployeeIDs.Count)
        {
            $EndIndex = $UniqueEmployeeIDs.Count - 1
        }

        $Batch = $UniqueEmployeeIDs[$i..$EndIndex]

        $LDAPFilter = New-EmployeeIDLDAPFilter `
            -EmployeeIDs $Batch `
            -AttributeName $EmployeeIDAttribute

        try
        {
            $Users = Get-ADUser `
                -Server $DomainServer `
                -LDAPFilter $LDAPFilter `
                -Properties $EmployeeIDAttribute,DisplayName,DistinguishedName

            foreach ($User in $Users)
            {
                $EmployeeID = "$($User.$EmployeeIDAttribute)".Trim()

                if ($EmployeeID)
                {
                    $UserKey = "$DomainServer|$EmployeeID"

                    $UserLookupCache[$UserKey] = [PSCustomObject]@{
                        DisplayName       = $User.DisplayName
                        DistinguishedName = $User.DistinguishedName
                        EmployeeID        = $EmployeeID
                        Domain            = $DomainServer
                    }
                }
            }
        }
        catch
        {
            Write-Warning "Failed querying $DomainServer"
            Write-Warning $_.Exception.Message
        }
    }
}

#=========================================================================
# MEMBERSHIP FUNCTION
#=========================================================================

function Test-CachedMembership
{
    param(
        [string]$UserDN,
        [hashtable]$Cache
    )

    if (-not $UserDN)
    {
        return "Not Present"
    }

    if ($Cache.ContainsKey($UserDN.ToUpper()))
    {
        return "Present"
    }

    return "Not Present"
}

#=========================================================================
# PROCESS USERS
#=========================================================================

Write-Host ""
Write-Host "Processing users..." -ForegroundColor Yellow

$Results = foreach ($Row in $InputUsers)
{
    $EmployeeID = "$($Row.EmployeeID)".Trim()

    if (-not $EmployeeID)
    {
        continue
    }

    $Output = [ordered]@{
        EmployeeID = $EmployeeID
    }

    $FirstFoundUser = $null

    foreach ($DomainServer in $Domains)
    {
        $UserKey = "$DomainServer|$EmployeeID"

        if ($UserLookupCache.ContainsKey($UserKey))
        {
            $FirstFoundUser = $UserLookupCache[$UserKey]
            break
        }
    }

    $Output["UserName"] = if ($FirstFoundUser)
    {
        $FirstFoundUser.DisplayName
    }
    else
    {
        "User Not Found"
    }

    foreach ($GroupEntry in $TargetGroups)
    {
        $GroupName    = "$($GroupEntry.GroupName)".Trim()
        $DomainServer = "$($GroupEntry.GroupDomain)".Trim()

        $GroupKey = "$DomainServer|$GroupName"
        $UserKey  = "$DomainServer|$EmployeeID"

        $ColumnName = "[$DomainServer] $GroupName"

        if ($UserLookupCache.ContainsKey($UserKey))
        {
            $User = $UserLookupCache[$UserKey]

            $Output[$ColumnName] = Test-CachedMembership `
                -UserDN $User.DistinguishedName `
                -Cache $GroupMembers[$GroupKey]
        }
        else
        {
            $Output[$ColumnName] = "Not Present"
        }
    }

    [PSCustomObject]$Output
}

#=========================================================================
# EXPORT RESULTS
#=========================================================================

$Results | Export-Csv `
    -Path $OutputFilePath `
    -NoTypeInformation `
    -Encoding UTF8

Write-Host ""
Write-Host "Completed Successfully" -ForegroundColor Green
Write-Host "Users Processed : $($Results.Count)" -ForegroundColor Green
Write-Host "Groups Audited  : $($TargetGroups.Count)" -ForegroundColor Green
Write-Host "Domains Audited : $($Domains.Count)" -ForegroundColor Green
Write-Host "Output File     : $OutputFilePath" -ForegroundColor Green

Read-Host "SCRIPT COMPLETED, press Enter"
