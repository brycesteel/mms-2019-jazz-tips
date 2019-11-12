<#
    .SYNOPSIS
        Removes Windows user profile entries pointing to the same profile image path NOT belonging to given domain SID.

    .DESCRIPTION
        Removes  Windows user profile entries from the registry Profile List (and matching Profile Guid entries)
        that point to the same profile image path ('C:\Users\<UserName>') when the user does NOT match a given domain SID.
        
        Makes a backup of of the 'ProfileList' and 'ProfileGuid' registry keys to '$env:TEMP' before any removals.

    .NOTES
        User Profile Entries Path: 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'
        User Profile Guid-to-SID Entries: 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileGuid'

        Author: Bryce Steel
        Version: 1.0
#>
[CmdletBinding()]
param(
    # Desired domain SID prefix for users (matching ProfileList entries are NOT removed)
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]
    $DesiredUserDomainSID
)

Write-Verbose "Configured to leave user ProfileList entries alone if they match the desired Domain SID of: $DesiredUserDomainSID"

# Get groups of ProfileList entries for normal users having the same / duplicate ProfileImagePath (grouped by ProfileImagePath)
$ProfileListEntriesHavingSameProfileImagePathGroups = @(
    # Get all ProfileList registry keys
    Get-ChildItem -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList' | 
        # Exclude "Special" profiles (built-in accounts)
        Where-Object {$_.PSChildName -match '^S-1-5-21-[0-9-]+$'} | 
        # Get all subkeys of each ProfileList entry
        Get-ItemProperty | 
        # Group the ProfileList entries by ProfileImagePath
        Group-Object -Property ProfileImagePath | 
        # Return only groups with multiple ProfileList entries having the same / duplicate ProfileImagePath
        Where-Object {$_.Count -ge 2}
)

# Identify ProfileList entries with a duplicate ProfileImagePath that can be removed (NOT having the desired Domain SID as a prefix)
# NOTE: Will NOT select "*.bak" ProfileList entries if they begin with / match desired Domain SID (separate cleanup required)
$ProfileListEntriesToRemove = @(
    $ProfileListEntriesHavingSameProfileImagePathGroups | ForEach-Object { 
        $_.Group | Where-Object {$_.PSChildName -notmatch "^$DesiredUserDomainSID-[0-9-]+"}
    }
)

if ($ProfileListEntriesToRemove.Count -gt 0) {
    Write-Verbose -Message "Found ProfileList entries TO REMOVE (having duplicate ProfileImagePath values and NOT belonging to desired Domain) of count: $($ProfileListEntriesToRemove.Count)"

    # Backup ProfileGuid and ProfileList reg keys before completing any cleanup
    try {
        $RegExePath = "$($env:SystemRoot)\System32\reg.exe"
        if (Test-Path -Path $RegExePath) {
            # Backup ProfileGuid reg keys
            $RegBackupDateTimeString = (Get-Date).ToString('yyyy-MM-dd-hhmm')
            $BeforeCleanupProfileGuidRegBackupFilePath = "$($env:TEMP)\RemoveAltDomainProfilesHavingDuplicateProfilePaths_ProfileGuid_BEFORE_$RegBackupDateTimeString.reg"
            Write-Verbose -Message "Attempting reg.exe backup of ProfileGuid registry keys to: '$BeforeCleanupProfileGuidRegBackupFilePath' ..."
            $ProfileGuidRegBackupProcess = Start-Process -FilePath $RegExePath -ArgumentList "EXPORT `"HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileGuid`" `"$BeforeCleanupProfileGuidRegBackupFilePath`" /y" -WindowStyle Hidden -Wait -PassThru
            if ($ProfileGuidRegBackupProcess.ExitCode -eq 0) {
                Write-Verbose "Completed reg.exe backup of ProfileGuid registry keys"
            } else {
                Write-Error "Failed to complete backup of ProfileGuid registry keys" -ErrorAction Stop
            }

            # Backup ProfileList reg keys
            $BeforeCleanupProfileListRegBackupFilePath = "$($env:TEMP)\RemoveAltDomainProfilesHavingDuplicateProfilePaths_ProfileList_BEFORE_$RegBackupDateTimeString.reg"
            Write-Verbose -Message "Attempting reg.exe backup of ProfileList registry keys to: '$BeforeCleanupProfileListRegBackupFilePath' ..."
            $ProfileListRegBackupProcess = Start-Process -FilePath $RegExePath -ArgumentList "EXPORT `"HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList`" `"$BeforeCleanupProfileListRegBackupFilePath`" /y" -WindowStyle Hidden -Wait -PassThru
            if ($ProfileListRegBackupProcess.ExitCode -eq 0) {
                Write-Verbose "Completed reg.exe backup of ProfileList registry keys"
            } else {
                Write-Error "Failed to complete backup of ProfileList registry keys" -ErrorAction Stop
            }
            
        } else {
            Write-Error "Unable to find / access reg.exe at: $RegExePath" -ErrorAction Stop
        }
    }
    catch {
        throw "Unable to complete reg.exe backup of ProfileGuid and/or ProfileList reg keys - exiting without further cleanup action : $($_.Exception.Message)"
    }

    # Attempt removal of each ProfileList entry first and then its corresponding ProfileGuid (if present)
    foreach ($ProfileListEntryToRemove in $ProfileListEntriesToRemove) {
        try {
            Write-Verbose -Message "Removing ProfileList entry / reg key and all its subkeys / properties: `t'$($ProfileListEntryToRemove.PSPath)'"
            Remove-Item -LiteralPath $ProfileListEntryToRemove.PSPath -Recurse -Force
            if ($ProfileListEntryToRemove.Guid -and (Test-Path -LiteralPath "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileGuid\$($ProfileListEntryToRemove.Guid)")) {
                Write-Verbose -Message "Removing corresponding ProfileGuid entry / reg key and all its subkeys / properties: `t'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileGuid\$($ProfileListEntryToRemove.Guid)'"
                Remove-Item -LiteralPath "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileGuid\$($ProfileListEntryToRemove.Guid)" -Recurse -Force
            }
        }
        catch {
            Write-Error -Message "Unable to complete removal of ProfileList entry and/or corresponding ProfileGuid reg keys: `t$($ProfileListEntryToRemove.PSPath), $($ProfileListEntryToRemove.Guid) :  $($_.Exception.Error)"
        }
    }

} else {
    Write-Verbose -Message "Did not find any ProfileList entries having duplicate ProfileImagePath values (not belonging to desired Domain) to safely remove."
}