<powershell>
# Windows Server 2022 - Active Directory Domain Services Setup
# This script installs AD DS, promotes the server to a domain controller,
# and creates test users/groups for Vault LDAP authentication testing.

$ErrorActionPreference = "Continue"

# Variables from Terraform
$DomainName = "${ad_domain_name}"
$NetBIOSName = "${ad_netbios_name}"
$SafeModePassword = ConvertTo-SecureString "${ad_safe_mode_password}" -AsPlainText -Force
$ServiceAccountPassword = ConvertTo-SecureString "${ad_admin_password}" -AsPlainText -Force
$TestUserPassword = ConvertTo-SecureString "${ad_test_user_password}" -AsPlainText -Force

# Log file for troubleshooting
$LogFile = "C:\AD-Setup.log"

function Write-Log {
    param([string]$Message)
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$Timestamp - $Message" | Out-File -Append -FilePath $LogFile
    Write-Host $Message
}

Write-Log "Starting Active Directory setup..."
Write-Log "Domain: $DomainName"
Write-Log "NetBIOS: $NetBIOSName"

# Step 1: Install AD DS Role
Write-Log "Installing AD DS role and management tools..."
try {
    Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools -ErrorAction Stop
    Write-Log "AD DS role installed successfully"
} catch {
    Write-Log "ERROR installing AD DS role: $_"
}

# Step 2: Install DNS Server (required for AD)
Write-Log "Installing DNS Server role..."
try {
    Install-WindowsFeature -Name DNS -IncludeManagementTools -ErrorAction Stop
    Write-Log "DNS Server role installed successfully"
} catch {
    Write-Log "ERROR installing DNS role: $_"
}

# Step 3: Promote to Domain Controller
Write-Log "Promoting server to Domain Controller..."
Write-Log "This will trigger a restart after completion."

try {
    Import-Module ADDSDeployment

    Install-ADDSForest `
        -DomainName $DomainName `
        -DomainNetbiosName $NetBIOSName `
        -SafeModeAdministratorPassword $SafeModePassword `
        -InstallDns:$true `
        -CreateDnsDelegation:$false `
        -DatabasePath "C:\Windows\NTDS" `
        -LogPath "C:\Windows\NTDS" `
        -SysvolPath "C:\Windows\SYSVOL" `
        -NoRebootOnCompletion:$false `
        -Force:$true `
        -ErrorAction Stop

    Write-Log "AD DS Forest installation initiated"
} catch {
    Write-Log "ERROR during AD DS promotion: $_"
}

# Note: The server will restart after AD DS promotion.
# The following script creates users after restart via scheduled task.

# Create a script to run after restart to create users
$PostRestartScript = @'
$ErrorActionPreference = "Continue"
$LogFile = "C:\AD-Setup.log"

function Write-Log {
    param([string]$Message)
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$Timestamp - $Message" | Out-File -Append -FilePath $LogFile
    Write-Host $Message
}

# Wait for AD DS to be fully operational
Write-Log "Waiting for AD DS to be fully operational..."
$MaxWait = 300  # 5 minutes
$Waited = 0
while ($Waited -lt $MaxWait) {
    try {
        Get-ADDomain -ErrorAction Stop | Out-Null
        Write-Log "AD DS is operational"
        break
    } catch {
        Write-Log "AD DS not ready yet, waiting..."
        Start-Sleep -Seconds 10
        $Waited += 10
    }
}

if ($Waited -ge $MaxWait) {
    Write-Log "ERROR: AD DS did not become operational in time"
    exit 1
}

# Import AD module
Import-Module ActiveDirectory

$DomainName = "YOURDOMAINHERE"
$ServiceAccountPassword = ConvertTo-SecureString "YOURSERVICEPASSHERE" -AsPlainText -Force
$TestUserPassword = ConvertTo-SecureString "YOURTESTUSERPASSHERE" -AsPlainText -Force

# Create Vault-related security groups
Write-Log "Creating Vault security groups..."

try {
    New-ADGroup -Name "Vault-Admins" `
        -GroupScope Global `
        -GroupCategory Security `
        -Description "Vault Administrators - maps to ldap-admins policy" `
        -Path "CN=Users,DC=$($DomainName.Split('.')[0]),DC=$($DomainName.Split('.')[1])" `
        -ErrorAction Stop
    Write-Log "Created group: Vault-Admins"
} catch {
    Write-Log "Group Vault-Admins may already exist: $_"
}

try {
    New-ADGroup -Name "Vault-Users" `
        -GroupScope Global `
        -GroupCategory Security `
        -Description "Vault Users - maps to ldap-users policy" `
        -Path "CN=Users,DC=$($DomainName.Split('.')[0]),DC=$($DomainName.Split('.')[1])" `
        -ErrorAction Stop
    Write-Log "Created group: Vault-Users"
} catch {
    Write-Log "Group Vault-Users may already exist: $_"
}

# Create service account for Vault LDAP bind
Write-Log "Creating Vault service account..."
try {
    New-ADUser -Name "vault-svc" `
        -SamAccountName "vault-svc" `
        -UserPrincipalName "vault-svc@$DomainName" `
        -Description "Service account for Vault LDAP authentication" `
        -AccountPassword $ServiceAccountPassword `
        -Enabled $true `
        -PasswordNeverExpires $true `
        -CannotChangePassword $true `
        -Path "CN=Users,DC=$($DomainName.Split('.')[0]),DC=$($DomainName.Split('.')[1])" `
        -ErrorAction Stop
    Write-Log "Created service account: vault-svc"
} catch {
    Write-Log "Service account vault-svc may already exist: $_"
}

# Create test users
Write-Log "Creating test users..."

# Alice - Vault Admin
try {
    New-ADUser -Name "Alice Admin" `
        -GivenName "Alice" `
        -Surname "Admin" `
        -SamAccountName "alice" `
        -UserPrincipalName "alice@$DomainName" `
        -Description "Test user - Vault Administrator" `
        -EmailAddress "alice@$DomainName" `
        -AccountPassword $TestUserPassword `
        -Enabled $true `
        -PasswordNeverExpires $true `
        -Path "CN=Users,DC=$($DomainName.Split('.')[0]),DC=$($DomainName.Split('.')[1])" `
        -ErrorAction Stop
    Add-ADGroupMember -Identity "Vault-Admins" -Members "alice" -ErrorAction Stop
    Write-Log "Created user: alice (member of Vault-Admins)"
} catch {
    Write-Log "User alice may already exist: $_"
}

# Bob - Vault User
try {
    New-ADUser -Name "Bob User" `
        -GivenName "Bob" `
        -Surname "User" `
        -SamAccountName "bob" `
        -UserPrincipalName "bob@$DomainName" `
        -Description "Test user - Vault User" `
        -EmailAddress "bob@$DomainName" `
        -AccountPassword $TestUserPassword `
        -Enabled $true `
        -PasswordNeverExpires $true `
        -Path "CN=Users,DC=$($DomainName.Split('.')[0]),DC=$($DomainName.Split('.')[1])" `
        -ErrorAction Stop
    Add-ADGroupMember -Identity "Vault-Users" -Members "bob" -ErrorAction Stop
    Write-Log "Created user: bob (member of Vault-Users)"
} catch {
    Write-Log "User bob may already exist: $_"
}

# Charlie - Vault User
try {
    New-ADUser -Name "Charlie User" `
        -GivenName "Charlie" `
        -Surname "User" `
        -SamAccountName "charlie" `
        -UserPrincipalName "charlie@$DomainName" `
        -Description "Test user - Vault User" `
        -EmailAddress "charlie@$DomainName" `
        -AccountPassword $TestUserPassword `
        -Enabled $true `
        -PasswordNeverExpires $true `
        -Path "CN=Users,DC=$($DomainName.Split('.')[0]),DC=$($DomainName.Split('.')[1])" `
        -ErrorAction Stop
    Add-ADGroupMember -Identity "Vault-Users" -Members "charlie" -ErrorAction Stop
    Write-Log "Created user: charlie (member of Vault-Users)"
} catch {
    Write-Log "User charlie may already exist: $_"
}

Write-Log "AD setup complete!"
Write-Log "Test users created: alice (Vault-Admins), bob (Vault-Users), charlie (Vault-Users)"
Write-Log "Service account: vault-svc"

# Clean up scheduled task
Unregister-ScheduledTask -TaskName "CreateADUsers" -Confirm:$false -ErrorAction SilentlyContinue
'@

# Replace placeholders in post-restart script
$PostRestartScript = $PostRestartScript -replace "YOURDOMAINHERE", $DomainName
$PostRestartScript = $PostRestartScript -replace "YOURSERVICEPASSHERE", "${ad_admin_password}"
$PostRestartScript = $PostRestartScript -replace "YOURTESTUSERPASSHERE", "${ad_test_user_password}"

# Save post-restart script
$PostRestartScript | Out-File -FilePath "C:\CreateADUsers.ps1" -Encoding UTF8

# Create scheduled task to run after restart
Write-Log "Creating scheduled task for post-restart user creation..."
$Action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-ExecutionPolicy Bypass -File C:\CreateADUsers.ps1"
$Trigger = New-ScheduledTaskTrigger -AtStartup
$Principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

Register-ScheduledTask -TaskName "CreateADUsers" `
    -Action $Action `
    -Trigger $Trigger `
    -Principal $Principal `
    -Settings $Settings `
    -Description "Create AD users for Vault testing after DC promotion" `
    -ErrorAction SilentlyContinue

Write-Log "Scheduled task created. Users will be created after server restart."
Write-Log "Initial setup complete. Server will restart for AD DS promotion."
</powershell>
