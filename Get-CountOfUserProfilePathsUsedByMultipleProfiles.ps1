# Get Count of User Profile Paths Used By Multiple Profiles
@(
    Get-ChildItem -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList' | 
        Where-Object {$_.PSChildName -match '^S-1-5-21-[0-9-]+$'} | 
        Get-ItemProperty | 
        Group-Object -Property ProfileImagePath | 
        Where-Object {$_.Count -gt 1}
).Count