
$FONT_FAMILY = "CascadiaCode"

# https://learn.microsoft.com/en-us/windows/win32/api/shldisp/ne-shldisp-shellspecialfolderconstants
$SHELL_SPECIAL_FOLDER_FONTS_CODE = 0x14

$fontInstallSuccess = $false

Set-Location -Path "cache"
try {
    # TODO improvement: remove progressbar (https://stackoverflow.com/questions/18770723/hide-progress-of-invoke-webrequest)
    # TODO tar.xz instead: zip is 40+MB while tar.xz is 3MB
    # Invoke-WebRequest -URI "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/$FONT_FAMILY.zip" -OutFile "$FONT_FAMILY.zip"
    # Expand-Archive -Path "./$FONT_FAMILY.zip" -DestinationPath "./fonts" -Force
    $fontFilesToInstall = Get-ChildItem -Path "./fonts" -Filter "*.ttf" | Select FullName
    $fontsFolder = (New-Object -ComObject shell.application).NameSpace($SHELL_SPECIAL_FOLDER_FONTS_CODE)
    Write-Output $fontsFolder
    Write-Output $fontFilesToInstall
    $fontFilesToInstall | ForEach-Object { $fontsFolder.CopyHere($_) }
    # TODO refresh font cache
    $fontInstallSuccess = $true
} catch {
    Write-Output "Error: $_"
}
Set-Location -Path ".."

# TODO
if (!$fontInstallSuccess) {

}

# rewrite of this...
# # install git (required for NerdFonts)
# Write-Output "Installing Git..."
# winget install Git.Git

# # install nerdfonts
# Write-Output "Installing NerdFonts version of Cascadia Code & Cascadia Mono..."
# Set-Location cache
# if (!(Test-Path -Path ./nerd-fonts)) {
#     git clone --depth 1 https://github.com/ryanoasis/nerd-fonts nerd-fonts
# } else {
#     Write-Output "NerdFonts git already cloned. If you want to update it, do it manually."
# }
# Set-Location nerd-fonts
# ./install.ps1 CascadiaCode, CascadiaMono
# Set-Location ../..
