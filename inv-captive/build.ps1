# Builds InvCaptive.jar against the local Paper server (NMS included).
# Usage: build.ps1 [-ServerDir <path to .server>] [-Output <jar path>]
Param(
    [string]$ServerDir = (Join-Path $PSScriptRoot "..\.server"),
    [string]$Output = (Join-Path $PSScriptRoot "build\InvCaptive.jar"),
    # Minecraft version to compile against (folder name under versions\). Empty = newest.
    [string]$McVersion = ""
)

$ErrorActionPreference = "Stop"

$Version = "0.2.0"
$JavaRelease = 25

# Locate the JDK that "java" on PATH belongs to
$Props = (cmd /c "java -XshowSettings:properties -version 2>&1")
$JavaHome = ($Props | Where-Object { $_ -match '^\s*java\.home\s*=' } | Select-Object -First 1) -replace '^\s*java\.home\s*=\s*', ''
$Javac = Join-Path $JavaHome "bin\javac.exe"
$JarTool = Join-Path $JavaHome "bin\jar.exe"
if (!(Test-Path $Javac) -or !(Test-Path $JarTool))
{
    throw "JDK not found (java.home=$JavaHome). Install a JDK $JavaRelease+ and put it on PATH."
}

# Classpath = patched Paper server + its libraries (created by paperclip)
$ServerDir = (Resolve-Path $ServerDir).Path
$VersionsDir = Join-Path $ServerDir "versions"
if ([string]::IsNullOrEmpty($McVersion))
{
    $Newest = Get-ChildItem $VersionsDir -Directory -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($Newest) { $McVersion = $Newest.Name }
}
# Only the requested version, so old server jars left over from upgrades do not end up on the classpath
$ServerJars = @(Get-ChildItem (Join-Path $VersionsDir $McVersion) -Filter *.jar -ErrorAction SilentlyContinue)
$LibraryJars = @(Get-ChildItem (Join-Path $ServerDir "libraries") -Recurse -Filter *.jar -ErrorAction SilentlyContinue)
if ($ServerJars.Count -eq 0)
{
    throw "Patched Paper jar not found in $ServerDir\versions. Run paper.jar once (or with -Dpaperclip.patchonly=true)."
}

$BuildDir = Join-Path $PSScriptRoot "build"
$Classes = Join-Path $BuildDir "classes"
if (Test-Path $Classes) { Remove-Item -Recurse -Force $Classes }
New-Item -ItemType Directory -Force $Classes | Out-Null

# Compile (argument file avoids the Windows command line length limit)
$Sources = @(Get-ChildItem (Join-Path $PSScriptRoot "src\main\java") -Recurse -Filter *.java | ForEach-Object { $_.FullName })
$ClassPath = (($ServerJars + $LibraryJars) | ForEach-Object { $_.FullName }) -join ";"
$ArgFile = Join-Path $BuildDir "javac.args"
$JavacArgs = @("--release", "$JavaRelease", "-encoding", "UTF-8", "-nowarn", "-d", $Classes, "-cp", $ClassPath) + $Sources
[IO.File]::WriteAllLines($ArgFile, ($JavacArgs | ForEach-Object { '"' + ($_ -replace '\\', '/') + '"' }))

& $Javac "@$ArgFile"
if ($LASTEXITCODE -ne 0) { throw "javac failed" }

# Resources (expand ${version})
$Resources = Join-Path $PSScriptRoot "src\main\resources"
Get-ChildItem $Resources -Recurse -File | ForEach-Object {
    $Dest = Join-Path $Classes $_.FullName.Substring($Resources.Length + 1)
    New-Item -ItemType Directory -Force (Split-Path $Dest) | Out-Null
    if ($_.Extension -eq ".yml")
    {
        $Text = [IO.File]::ReadAllText($_.FullName).Replace('${version}', $Version)
        [IO.File]::WriteAllText($Dest, $Text, (New-Object Text.UTF8Encoding $false))
    }
    else
    {
        Copy-Item $_.FullName $Dest
    }
}

# Package
New-Item -ItemType Directory -Force (Split-Path $Output) | Out-Null
if (Test-Path $Output) { Remove-Item -Force $Output }
& $JarTool --create --file $Output -C $Classes .
if ($LASTEXITCODE -ne 0) { throw "jar failed" }

Write-Host "Built $Output"
