$image = "~/.config/winfetch/image.png"
$imgwidth = 24

$ShowDisks = @("*")

$ShowPkgs = @("winget")

$memorystyle = 'bartext'
$diskstyle = 'bartext'
$batterystyle = 'bartext'

@(
    "title"
    "dashes"
    "os"
    "uptime"
    "pwsh"
    "resolution"
    "terminal"
    "cpu"
    "memory"
    "disk"
    "battery"
    "blank"
    "colorbar"
)
