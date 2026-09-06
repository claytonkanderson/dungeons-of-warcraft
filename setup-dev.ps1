# Set up a fresh Windows machine for developing Dungeons of Warcraft.
#
#   git clone https://github.com/claytonkanderson/dungeons-of-warcraft.git
#   cd dungeons-of-warcraft
#   powershell -ExecutionPolicy Bypass -File setup-dev.ps1
#
# Installs Godot 4.7.2 (the pinned engine) through winget, the Python
# packages the pipeline needs, then looks for both game installs and, when
# both are found, builds the assets into .\assets (5-10 minutes). Re-run it
# any time; every step is a no-op once done.

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

Write-Host "== Godot 4.7.2"
$godot = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64.exe"
if (Test-Path $godot) {
    Write-Host "   already installed: $godot"
} else {
    winget install --id GodotEngine.GodotEngine --version 4.7.2 --exact --accept-package-agreements --accept-source-agreements
    if (-not (Test-Path $godot)) {
        Write-Host "   winget finished but the executable is not at the expected path;"
        Write-Host "   set DOW_GODOT to wherever Godot_v4.7.2-stable_win64.exe landed."
    }
}

Write-Host "== Python packages"
python --version
python -m pip install --quiet --upgrade pillow numpy pyinstaller
python -c "import PIL, numpy; print('   pillow', PIL.__version__, ' numpy', numpy.__version__)"

Write-Host "== Game installs"
$detect = python pipeline/builder.py --detect 2>&1 | Select-String "Diablo II:|World of Warcraft:"
$detect | ForEach-Object { Write-Host "   $_" }
$missing = $detect | Select-String "not found"
if ($missing) {
    Write-Host ""
    Write-Host "   A game was not found. Diablo II: run the Blizzard downloader (Downloader_Diablo2_*.exe)"
    Write-Host "   and install Diablo II and then Lord of Destruction; WoW: install WoW Classic"
    Write-Host "   Anniversary Edition from Battle.net and let it finish downloading. Then re-run"
    Write-Host "   this script, or pass the folders yourself:"
    Write-Host '   python pipeline/builder.py --d2 "C:\...\Diablo II" --wow "C:\...\World of Warcraft"'
    exit 1
}

if (Test-Path (Join-Path $root "assets\gamedata.json")) {
    Write-Host "== Assets already built in .\assets (delete the folder to rebuild)"
} else {
    Write-Host "== Building assets into .\assets (5-10 minutes)"
    python pipeline/builder.py --out assets
}

Write-Host ""
Write-Host "Ready. run_game.bat launches the game; see DEVELOPMENT.md for the rest."
