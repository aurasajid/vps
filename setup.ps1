param(
    [string]$Password = "luffy@123"
)

Write-Host "[-] Configuring Remote Desktop (RDP)..."
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 0
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name "UserAuthentication" -Value 0
Enable-NetFirewallRule -DisplayGroup "Remote Desktop"

Write-Host "[-] Configuring user account 'luffy'..."
$userExists = net user luffy 2>&1
if ($LASTEXITCODE -ne 0) {
    net user luffy $Password /add /expires:never /active:yes
} else {
    net user luffy $Password
}
net localgroup "Administrators" luffy /add
net localgroup "Remote Desktop Users" luffy /add

Write-Host "[-] Updating 'runneradmin' password..."
net user runneradmin $Password

Write-Host "[-] Installing Google Chrome..."
choco install googlechrome -y --no-progress

Write-Host "[-] Python status:"
python --version

Write-Host "[+] Windows setup complete!"
