# Create AD Users and Groups for Vault Testing
# Run this script on the Windows AD server if users weren't created automatically
# Usage: .\create-ad-users.ps1 -DomainName "vaultlab.local" -ServicePassword "VaultBind123!" -TestUserPassword "Password123!"

param(
    [string]$DomainName = "vaultlab.local",
    [string]$ServicePassword = "VaultBind123!",
    [string]$TestUserPassword = "Password123!"
)

$ErrorActionPreference = "Continue"

# Import Active Directory module
Import-Module ActiveDirectory

# Convert passwords to secure strings
$SecureServicePassword = ConvertTo-SecureString $ServicePassword -AsPlainText -Force
$SecureTestUserPassword = ConvertTo-SecureString $TestUserPassword -AsPlainText -Force

# Get domain info
$DomainParts = $DomainName.Split('.')
$BaseDN = "DC=$($DomainParts[0]),DC=$($DomainParts[1])"
$UsersOU = "CN=Users,$BaseDN"

Write-Host "Creating AD objects for Vault testing..."
Write-Host "Domain: $DomainName"
Write-Host "Base DN: $BaseDN"
Write-Host ""

# Create Security Groups
Write-Host "Creating security groups..."

try {
    New-ADGroup -Name "Vault-Admins" `
        -GroupScope Global `
        -GroupCategory Security `
        -Description "Vault Administrators - maps to ldap-admins policy" `
        -Path $UsersOU
    Write-Host "  Created: Vault-Admins"
} catch {
    Write-Host "  Vault-Admins already exists or error: $_" -ForegroundColor Yellow
}

try {
    New-ADGroup -Name "Vault-Users" `
        -GroupScope Global `
        -GroupCategory Security `
        -Description "Vault Users - maps to ldap-users policy" `
        -Path $UsersOU
    Write-Host "  Created: Vault-Users"
} catch {
    Write-Host "  Vault-Users already exists or error: $_" -ForegroundColor Yellow
}

Write-Host ""

# Create Service Account
Write-Host "Creating service account for Vault..."

try {
    New-ADUser -Name "vault-svc" `
        -SamAccountName "vault-svc" `
        -UserPrincipalName "vault-svc@$DomainName" `
        -Description "Service account for Vault LDAP authentication" `
        -AccountPassword $SecureServicePassword `
        -Enabled $true `
        -PasswordNeverExpires $true `
        -CannotChangePassword $true `
        -Path $UsersOU
    Write-Host "  Created: vault-svc"
} catch {
    Write-Host "  vault-svc already exists or error: $_" -ForegroundColor Yellow
}

Write-Host ""

# Create Test Users
Write-Host "Creating test users..."

# Alice - Vault Admin
try {
    New-ADUser -Name "Alice Admin" `
        -GivenName "Alice" `
        -Surname "Admin" `
        -SamAccountName "alice" `
        -UserPrincipalName "alice@$DomainName" `
        -Description "Test user - Vault Administrator" `
        -EmailAddress "alice@$DomainName" `
        -AccountPassword $SecureTestUserPassword `
        -Enabled $true `
        -PasswordNeverExpires $true `
        -Path $UsersOU
    Add-ADGroupMember -Identity "Vault-Admins" -Members "alice"
    Write-Host "  Created: alice (member of Vault-Admins)"
} catch {
    Write-Host "  alice already exists or error: $_" -ForegroundColor Yellow
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
        -AccountPassword $SecureTestUserPassword `
        -Enabled $true `
        -PasswordNeverExpires $true `
        -Path $UsersOU
    Add-ADGroupMember -Identity "Vault-Users" -Members "bob"
    Write-Host "  Created: bob (member of Vault-Users)"
} catch {
    Write-Host "  bob already exists or error: $_" -ForegroundColor Yellow
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
        -AccountPassword $SecureTestUserPassword `
        -Enabled $true `
        -PasswordNeverExpires $true `
        -Path $UsersOU
    Add-ADGroupMember -Identity "Vault-Users" -Members "charlie"
    Write-Host "  Created: charlie (member of Vault-Users)"
} catch {
    Write-Host "  charlie already exists or error: $_" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "AD user creation complete!"
Write-Host ""
Write-Host "Summary:"
Write-Host "  Service Account: vault-svc@$DomainName"
Write-Host "  Test Users: alice, bob, charlie"
Write-Host "  Groups: Vault-Admins, Vault-Users"
Write-Host ""
Write-Host "To verify, run:"
Write-Host "  Get-ADUser -Filter * | Select-Object SamAccountName"
Write-Host "  Get-ADGroup -Filter 'Name -like ""Vault*""' | Select-Object Name"
