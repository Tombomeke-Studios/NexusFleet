# Loader: dot-sources every script in src/, folder by folder, in a fixed order.
# Contracts (core) load first and the cmdlets (public) last, so the classes and
# module-level variables a file relies on already exist when it loads.
# Which functions the user sees is decided by FunctionsToExport in NexusFleet.psd1.

$sourceFolders = 'core', 'utils', 'transports', 'api', 'steps', 'public'

foreach ($folder in $sourceFolders) {
    $folderPath = Join-Path -Path $PSScriptRoot -ChildPath "src/$folder"
    if (-not (Test-Path -Path $folderPath -PathType Container)) {
        throw "NexusFleet cannot load: source folder '$folderPath' is missing."
    }

    # Sorted by name so the order inside a folder is the same on Windows and Linux.
    $files = Get-ChildItem -Path $folderPath -Filter '*.ps1' -File | Sort-Object -Property Name
    foreach ($file in $files) {
        try {
            . $file.FullName
        }
        catch {
            throw "NexusFleet cannot load '$($file.FullName)': $_"
        }
    }
}
