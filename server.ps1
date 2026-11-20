# Paper 서버 실행 스크립트 (InvCaptive for Paper 26.3)
#
# Original work: server.ps1 from InvCaptive 0.2.0 by Noonmaru
#   https://github.com/monun/inv-captive - GPL-3.0
#
# Modified 2026-11-20 by kaneteulin:
#   - PaperMC Fill v3 API로 Paper 다운로드 (SHA-256 검증), Java 버전 확인, 권장 JVM 플래그
#   - InvCaptive 직접 빌드 / GitHub Releases 다운로드, reset.bat 설치
#   - TLS 1.2, 백업 예외 목록, 재시작 선택 대기 등 수정
#
# This program is free software: you can redistribute it and/or modify it under the terms of
# the GNU General Public License as published by the Free Software Foundation, version 3.
# This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
# without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See the GNU General Public License (LICENSE.md) for more details.

# InvCaptive 설치 (서버 시작/재시작 때마다)
#  - 이 스크립트 옆에 inv-captive 폴더(소스)가 있으면: 직접 빌드해서 설치 (개발용, JDK 필요)
#  - 없으면: GitHub Releases 에서 최신 InvCaptive.jar, reset.bat 다운로드
$Build = $true
$PluginProject = "inv-captive"
$GitHubRepo = "kaneteulin/inv-captive"

# JVM
$Xms = "8G"
$Xmx = "8G"
$Debug = $false
$Jar = "paper.jar"
$UseRecommendedFlags = $true   # PaperMC API가 권장하는 JVM 플래그 사용

# Paper
# 특정 버전(예: "26.3")을 지정하거나 "latest"로 두면 최신 안정 버전을 자동으로 받습니다.
$Version = "26.3"

# Plugins
# (InvCaptive는 위 $Build로 직접 빌드하므로 여기에 넣지 않음)
$Plugins = @(
    "https://github.com/dmulloy2/ProtocolLib/releases/latest/download/ProtocolLib.jar"
)

# Backup
$AskBackup = $false

# PowerShell 5.1은 기본적으로 TLS 1.2를 쓰지 않아 GitHub/PaperMC 다운로드가 실패할 수 있음
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# PaperMC API는 User-Agent를 요구함
$UserAgent = "server-ps1/2.0"
$PaperApi = "https://fill.papermc.io/v3/projects/paper"

Function Download-File
{
    [CmdletBinding()]
    Param (
        [string]$Url,
        [string]$Folder,
        [Parameter(Mandatory = $False)] [string]$Filename,
        [switch]$Force
    )

    Create-Directory $Folder

    $Destfolder = (Resolve-Path $Folder).Path
    $WebResponse = $null

    try
    {
        $WebRequest = [System.Net.HttpWebRequest]::Create($Url)
        $WebRequest.Method = "GET"
        $WebRequest.UserAgent = $UserAgent
        $WebResponse = $WebRequest.GetResponse()

        if ([string]::IsNullOrEmpty($Filename))
        {
            $Disposition = $WebResponse.Headers['Content-Disposition']

            if ([string]::IsNullOrEmpty($Disposition))
            {
                $Filename = [System.IO.Path]::GetFileName($WebResponse.ResponseUri.AbsolutePath)
            }
            else
            {
                $Filename = [System.Net.Mime.ContentDisposition]::new($Disposition).FileName
            }
        }

        $Dest = Join-Path $Destfolder $Filename
        $FileInfo = [System.IO.FileInfo]$Dest

        if (Test-Path $Dest)
        {
            if (!$Force -and [datetime]::Compare($WebResponse.LastModified, $FileInfo.LastWriteTime) -eq 0)
            {
                Write-Host "UP-TO-DATE $Filename ($Url)"
                return
            }
            Write-Host "Updating $Filename from $Url"
        }
        else
        {
            Write-Host "Downloading $Filename from $Url"
        }

        $ResponseStream = $WebResponse.GetResponseStream()
        $FileWriter = New-Object System.IO.FileStream ($Dest, [System.IO.FileMode]::Create)
        try
        {
            $ResponseStream.CopyTo($FileWriter)
        }
        finally
        {
            $FileWriter.Close()
            $ResponseStream.Close()
        }
        $FileInfo.LastWriteTime = $WebResponse.LastModified
    }
    catch
    {
        Write-Host "  Failed to download $Url - $($_.Exception.Message)" -ForegroundColor Red
    }
    finally
    {
        if ($WebResponse) { $WebResponse.Dispose() }
    }
}

Function Create-Directory([string]$PathName)
{
    if (!(Test-Path $PathName))
    {
        New-Item $PathName -Type Directory | Out-Null
    }
}

Function Agree-EULA
{
    $Eula = "eula.txt"
    if (!(Test-Path $Eula))
    {
        New-Item $Eula -ItemType "file" | Out-Null
        Add-Content $Eula "eula=true"
    }
}

Function Invoke-PaperApi([string]$Path)
{
    return Invoke-RestMethod "$PaperApi$Path" -Headers @{ "User-Agent" = $UserAgent }
}

Function Resolve-PaperVersion([string]$Version)
{
    if ($Version -ne "latest")
    {
        return $Version
    }

    # versions는 최신 그룹부터 정렬되어 있음 (예: 26.3, 26.2, ...)
    $Project = Invoke-PaperApi ""
    foreach ($Group in $Project.versions.PSObject.Properties)
    {
        $Stable = $Group.Value | Where-Object { $_ -notmatch "-" } | Select-Object -First 1
        if ($Stable)
        {
            return $Stable
        }
    }
    throw "Paper 최신 버전을 찾을 수 없습니다."
}

Function Update-Paper([string]$Version, [string]$Jar)
{
    $PaperBuild = Invoke-PaperApi "/versions/$Version/builds/latest"
    $Download = $PaperBuild.downloads.'server:default'

    if ((Test-Path $Jar) -and ((Get-FileHash $Jar -Algorithm SHA256).Hash -eq $Download.checksums.sha256))
    {
        Write-Host "UP-TO-DATE paper $Version build $($PaperBuild.id)"
        return
    }

    Write-Host "Paper $Version build $($PaperBuild.id) ($($PaperBuild.channel))"
    Download-File $Download.url "." $Jar -Force

    if (!(Test-Path $Jar) -or (Get-FileHash $Jar -Algorithm SHA256).Hash -ne $Download.checksums.sha256)
    {
        throw "paper.jar 체크섬이 일치하지 않습니다. 다운로드를 다시 시도하세요."
    }
}

Function Get-JavaMajorVersion
{
    $Output = (& java -version 2>&1 | ForEach-Object { "$_" }) -join "`n"
    if ($Output -match 'version "(\d+)(?:\.(\d+))?')
    {
        if ($Matches[1] -eq "1") { return [int]$Matches[2] }   # 1.8 -> 8
        return [int]$Matches[1]
    }
    return 0
}

function Choice
{
    Param(
        [string]$Prompt,
        [string]$Choice,
        [char]$Default,
        [int]$Seconds
    )

    $Choice = $Choice.ToUpper()
    $Deadline = (Get-Date).AddSeconds($Seconds)

    Write-Host $Prompt

    $Choose = $Default

    while ((Get-Date) -lt $Deadline)
    {
        if ($host.UI.RawUI.KeyAvailable)
        {
            [string]$Key = ($host.UI.RawUI.ReadKey("IncludeKeyDown,NoEcho")).character
            $Key = $Key.ToUpper().ToCharArray()[0]

            if ($Choice.Contains($Key))
            {
                $Choose = $Key
                Break
            }
        }

        Start-Sleep -Milliseconds 50
    }

    Write-Host $Choose

    return $Choose
}

Function Backup
{
    if (!(Get-Command 7z -ErrorAction SilentlyContinue))
    {
        Write-Host "7z를 찾을 수 없어 백업을 건너뜁니다. 7-Zip을 PATH에 추가하세요." -ForegroundColor Yellow
        return
    }

    $Backup = "backup"

    Create-Directory $Backup

    $Date = Get-Date -Format "yyyy-MM-dd HHmmss"
    $ArchiveName = "$Backup/$Date.zip"
    7z a -tzip $ArchiveName ./ "-xr!*.gz" "-x!$Jar" "-x!backup" "-x!cache" "-x!libraries" "-x!versions" | Out-Null

    if ($LASTEXITCODE -eq 0)
    {
        Write-Host "Backup completed $ArchiveName"
    }
    else
    {
        Write-Host "Backup failed (7z exit code $LASTEXITCODE)" -ForegroundColor Red
    }
}

Function Install-InvCaptive
{
    if (Test-Path (Join-Path $ProjectFolder "$PluginProject\build.ps1"))
    {
        Invoke-PluginBuild
    }
    elseif ($GitHubRepo)
    {
        $Release = "https://github.com/$GitHubRepo/releases/latest/download"
        Download-File "$Release/InvCaptive.jar" "plugins" "InvCaptive.jar"
        Download-File "$Release/reset.bat" "plugins\InvCaptive" "reset.bat"
    }
    else
    {
        Write-Host "InvCaptive 소스(inv-captive 폴더)도, `$GitHubRepo 설정도 없어 InvCaptive를 설치하지 않습니다." -ForegroundColor Yellow
    }
}

Function Invoke-PluginBuild
{
    $ProjectDir = Join-Path $ProjectFolder $PluginProject
    $DataFolder = "plugins\InvCaptive"
    Create-Directory "plugins"
    Create-Directory $DataFolder

    # reset.bat (월드/시드 초기화 스크립트) 설치 - 빌드 성공 여부와 관계없이 항상 최신본으로
    $ResetBat = Join-Path $ProjectDir "reset.bat"
    if (Test-Path $ResetBat)
    {
        Copy-Item $ResetBat "$DataFolder\reset.bat" -Force
    }

    # 플러그인은 서버 내부 코드(NMS)를 참조하므로 현재 버전의 패치된 서버 jar가 있어야 컴파일 가능
    if (!(Get-ChildItem "versions\$Version" -Filter *.jar -ErrorAction SilentlyContinue))
    {
        Write-Host "Preparing Paper $Version server jar for plugin build..."
        java "-Dpaperclip.patchonly=true" -jar $Jar | Out-Null
    }

    $BuildScript = Join-Path $ProjectDir "build.ps1"
    $Output = Join-Path $ProjectDir "build\InvCaptive.jar"

    powershell -NoProfile -ExecutionPolicy Bypass -File $BuildScript -ServerDir (Get-Location).Path -McVersion $Version -Output $Output

    if ($LASTEXITCODE -ne 0)
    {
        Write-Host "InvCaptive 빌드 실패 - 기존 플러그인으로 서버를 시작합니다." -ForegroundColor Red
        return
    }

    Copy-Item $Output "plugins\InvCaptive.jar" -Force
    Write-Host "Installed InvCaptive.jar, reset.bat"
}

$ProjectFolder = $PSScriptRoot
Set-Location $ProjectFolder

$Folder = ".$( [System.IO.Path]::GetFileNameWithoutExtension($PSCommandPath) )"

# Setup
Create-Directory $Folder
Set-Location $Folder
Agree-EULA

# Download paper
$Version = Resolve-PaperVersion $Version
$host.UI.RawUI.WindowTitle = "paper $Version"
$VersionInfo = (Invoke-PaperApi "/versions/$Version").version

$JavaMin = [int]$VersionInfo.java.version.minimum
$JavaVersion = Get-JavaMajorVersion
if ($JavaVersion -lt $JavaMin)
{
    Write-Host "Paper $Version 은(는) Java $JavaMin 이상이 필요합니다. 현재 Java: $JavaVersion" -ForegroundColor Red
    Set-Location $ProjectFolder
    return
}

Update-Paper $Version $Jar

# Download plugins
foreach ($Plugin in $Plugins)
{
    Download-File $Plugin "plugins"
}

# Build JVM args
$JVMArgs = [System.Collections.ArrayList]@(
"-Xms$Xms",
"-Xmx$Xmx"
)

if ($UseRecommendedFlags -and $VersionInfo.java.flags.recommended)
{
    foreach ($Flag in $VersionInfo.java.flags.recommended)
    {
        [void]$JVMArgs.Add($Flag)
    }
}

# InvCaptive는 서버 내부 인벤토리의 final 필드를 교체함 (Java 26+에서 경고 제거 및 향후 차단 대비)
if ($JavaVersion -ge 26)
{
    [void]$JVMArgs.Add("--enable-final-field-mutation=ALL-UNNAMED")
}

if ($Debug)
{
    [void]$JVMArgs.Add("-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=*:5005")
}

[void]$JVMArgs.Add("-jar")
[void]$JVMArgs.Add($Jar)
[void]$JVMArgs.Add("--nogui")

# Run
While ($true)
{
    if ($Build)
    {
        Install-InvCaptive
    }

    java $JVMArgs

    if ($AskBackup)
    {
        $SkipBackup = Choice "Skip the backup? [Y]es, [N]o" "YN" 'N' 3

        if ($SkipBackup -eq 'N')
        {
            Backup
        }
    }

    $Restart = Choice "Restart? [Y]es [N]o" "YN" 'Y' 2

    if ($Restart -eq 'N')
    {
        Set-Location $ProjectFolder
        Break
    }
}
