<#
    Creates the directory junctions this addon needs to restore its settings.

    The Forever beta writes SavedVariables but never restores them, so the TOC
    loads the saved file itself through these junctions.  Run once, from the
    addon folder.  Junctions do not need administrator rights.
#>

$addon = $PSScriptRoot
$base = (Get-Item $addon).Parent.Parent.Parent.FullName   # ..\Interface\AddOns\<addon>
$accounts = Join-Path $base "WTF\Account"

if (-not (Test-Path $accounts)) {
    Write-Host "Could not find $accounts" -ForegroundColor Red
    Write-Host "Run this from inside Interface\AddOns\SquawkSpy in your game folder."
    exit 1
}

$index = 0
Get-ChildItem $accounts -Directory |
    Where-Object { Test-Path (Join-Path $_.FullName "SavedVariables") } |
    ForEach-Object {
        $index++
        $link = Join-Path $addon "SV$index"
        $target = Join-Path $_.FullName "SavedVariables"

        if (Test-Path $link) {
            Write-Host "SV$index already exists"
        } else {
            cmd /c mklink /J "`"$link`"" "`"$target`"" | Out-Null
            Write-Host "SV$index -> $($_.Name)"
        }

        # Placeholders stop the client logging "Error loading" for files that
        # do not exist until the first logout.  SpyF.lua is the old name of
        # this addon, read once so your KoS list carries over.
        foreach ($name in @("SquawkSpy.lua", "SpyF.lua")) {
            $file = Join-Path $link $name
            if (-not (Test-Path $file)) {
                "-- Placeholder; WoW overwrites this with the real database at logout." |
                    Out-File -FilePath $file -Encoding ascii
            }
        }
    }

if ($index -eq 0) {
    Write-Host "No account folders with SavedVariables found." -ForegroundColor Yellow
} else {
    Write-Host "`nDone. $index account folder(s) linked." -ForegroundColor Green
}
