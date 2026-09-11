#Requires -Version 5.1
<#
.SYNOPSIS
    One-command Core3 development server in Docker on Windows, with no
    user-managed WSL distro.

.DESCRIPTION
    Docker Desktop's WSL2 backend runs in its own auto-managed distro, so nothing
    here requires installing or configuring a WSL instance of your own.

    The container builds from a clone of THIS repository made inside the
    container, not from a bind mount of the working tree. Two reasons:
      * This checkout has core.autocrlf=true, so the working tree is CRLF and
        would not build under Linux.
      * Build output stays on a Linux-native Docker volume instead of crossing
        the host filesystem boundary, which is far faster.
    The consequence: only COMMITTED work reaches the container. Commit, then run
    'sync' inside the container to pull the new commits.

.PARAMETER Action
    up       Start (creating if needed) and attach to the container. Default.
    shell    Open an extra shell in the already-running container.
    stop     Stop the container.
    rebuild  Rebuild the Docker image, then start.
    reset    Delete the container and its home volume, discarding the build tree
             and database, then start fresh. Keeps the TRE volume.
    logs     Tail container output.

.PARAMETER TrePath
    Folder holding the client .tre files. Copied into the 'shared-tre' volume on
    first use.

.EXAMPLE
    .\core3.ps1

.EXAMPLE
    .\core3.ps1 rebuild
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('up', 'shell', 'stop', 'rebuild', 'reset', 'logs')]
    [string]$Action = 'up',

    [string]$TrePath = 'C:\Programs\SWGEmu',

    [int]$MemoryGB = 16,

    [int]$Processors = 16,

    # Leave %USERPROFILE%\.wslconfig alone.
    [switch]$SkipHostConfig
)

$ErrorActionPreference = 'Stop'

$Image         = 'swgemu/core3-dev:latest'
$Container     = 'swgemu-core3'
$HomeVolume    = 'swgemu-core3'
$TreVolume     = 'shared-tre'
$RepoRoot      = Split-Path -Parent $PSScriptRoot
$DockerContext = $PSScriptRoot

# Matches PORT_GROUP=44 in docker/Dockerfile.
$PortMap = @(
    '2222:2222/tcp',    # ssh
    '44453:44453/udp',  # login
    '44455:44455/tcp',  # status
    '44462:44462/udp',  # ping
    '44463:44463/udp'   # zone
)

function Write-Step { param([string]$Message) Write-Host "==> $Message" -ForegroundColor Cyan }
function Write-Note { param([string]$Message) Write-Host "    $Message" -ForegroundColor DarkGray }
function Write-Warn { param([string]$Message) Write-Host "!!! $Message" -ForegroundColor Yellow }

function Test-DockerDaemon {
    docker info 2>&1 | Out-Null
    return ($LASTEXITCODE -eq 0)
}

function Wait-DockerDaemon {
    param([int]$TimeoutSeconds = 180)

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)

    while ((Get-Date) -lt $deadline) {
        if (Test-DockerDaemon) { return }
        Start-Sleep -Seconds 3
    }

    throw "Docker daemon did not become ready within $TimeoutSeconds seconds."
}

function Start-DockerDesktop {
    $exe = 'C:\Program Files\Docker\Docker\Docker Desktop.exe'

    if (-not (Test-Path -LiteralPath $exe)) {
        throw "Docker Desktop not found at '$exe'. Install Docker Desktop, then re-run."
    }

    Write-Step 'Starting Docker Desktop...'
    Start-Process -FilePath $exe | Out-Null
    Wait-DockerDaemon
}

function Restart-DockerDesktop {
    Write-Step 'Restarting Docker Desktop to apply the new memory limit...'

    docker desktop stop 2>&1 | Out-Null

    if ($LASTEXITCODE -ne 0) {
        Get-Process -Name 'Docker Desktop' -ErrorAction SilentlyContinue | Stop-Process -Force
        Start-Sleep -Seconds 5
    }

    # Recycle the WSL VM so it re-reads .wslconfig.
    wsl --shutdown 2>&1 | Out-Null

    Start-DockerDesktop
}

function Set-WslMemory {
    # Under Docker Desktop's WSL2 backend the Resources memory slider is inert;
    # the VM's memory comes from %USERPROFILE%\.wslconfig and the container
    # inherits it. Returns $true when the file was changed.
    param([int]$MemoryGB, [int]$Processors)

    $path    = Join-Path $env:USERPROFILE '.wslconfig'
    $desired = [ordered]@{
        memory     = "${MemoryGB}GB"
        processors = "$Processors"
        swap       = "${MemoryGB}GB"
    }

    $lines = New-Object 'System.Collections.Generic.List[string]'

    if (Test-Path -LiteralPath $path) {
        foreach ($line in @(Get-Content -LiteralPath $path)) { [void]$lines.Add([string]$line) }
    }

    # Locate the [wsl2] section, creating it if the file has none.
    $header = -1

    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*\[wsl2\]\s*$') { $header = $i; break }
    }

    if ($header -lt 0) {
        $lines.Insert(0, '[wsl2]')
        $header = 0
    }

    # Only rewrite keys inside that section, so a same-named key under another
    # section header is left alone.
    $sectionEnd = $lines.Count

    for ($i = $header + 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*\[') { $sectionEnd = $i; break }
    }

    $changed = $false

    foreach ($key in $desired.Keys) {
        $value = $desired[$key]
        $index = -1

        for ($i = $header + 1; $i -lt $sectionEnd; $i++) {
            if ($lines[$i] -match "^\s*$key\s*=") { $index = $i; break }
        }

        if ($index -ge 0) {
            if ($lines[$index] -ne "$key=$value") {
                Write-Note ".wslconfig: $($lines[$index].Trim()) -> $key=$value"
                $lines[$index] = "$key=$value"
                $changed = $true
            }
        }
        else {
            Write-Note ".wslconfig: added $key=$value"
            $lines.Insert($header + 1, "$key=$value")
            $sectionEnd++
            $changed = $true
        }
    }

    if ($changed) {
        Set-Content -LiteralPath $path -Value $lines.ToArray() -Encoding ASCII
    }

    return $changed
}

function Initialize-Host {
    $wasRunning = Test-DockerDaemon

    if ($SkipHostConfig) {
        if (-not $wasRunning) { Start-DockerDesktop }
        return
    }

    $settings = Join-Path $env:APPDATA 'Docker\settings.json'
    $isWsl2   = $true

    if (Test-Path -LiteralPath $settings) {
        try {
            $isWsl2 = [bool](Get-Content -Raw -LiteralPath $settings | ConvertFrom-Json).wslEngineEnabled
        }
        catch {
            Write-Note 'Could not read Docker Desktop settings; assuming the WSL2 backend.'
        }
    }

    if (-not $isWsl2) {
        Write-Warn 'Docker Desktop is on the Hyper-V backend, so .wslconfig does not apply.'
        Write-Warn "Set memory to ${MemoryGB}GB under Docker Desktop > Settings > Resources."
        if (-not $wasRunning) { Start-DockerDesktop }
        return
    }

    Write-Step "Ensuring the Docker VM has ${MemoryGB}GB RAM and $Processors CPUs..."

    $changed = Set-WslMemory -MemoryGB $MemoryGB -Processors $Processors

    if (-not $changed) { Write-Note 'Already configured.' }

    # The VM only reads .wslconfig when it boots, so a change needs a recycle --
    # but only if it is already up. A cold start picks the new values up for free.
    if ($changed -and $wasRunning) {
        Restart-DockerDesktop
    }
    elseif (-not (Test-DockerDaemon)) {
        Start-DockerDesktop
    }
}

function Initialize-Image {
    param([switch]$Force)

    docker image inspect $Image 2>&1 | Out-Null

    if ($LASTEXITCODE -eq 0 -and -not $Force) {
        Write-Note "Image $Image already built."
        return
    }

    Write-Step "Building $Image (first build is long: clang toolchain plus deps)..."

    docker build --progress=plain -t $Image $DockerContext

    if ($LASTEXITCODE -ne 0) { throw 'docker build failed.' }
}

function Get-TreVolumeCount {
    # --entrypoint bash is required: the image entrypoint (/run.sh) execs "$@"
    # unquoted, which word-splits the -c script and lets the host expand globs.
    $out = docker run --rm -v "${TreVolume}:/tre" --entrypoint bash $Image `
        -c 'ls -1 /tre/*.tre 2> /dev/null | wc -l' 2>&1

    $line = @($out) | Where-Object { "$_".Trim() -match '^\d+$' } | Select-Object -Last 1

    if ($null -eq $line) { return -1 }

    return [int]"$line".Trim()
}

function Initialize-TreVolume {
    $count = Get-TreVolumeCount

    if ($count -lt 0) {
        Write-Warn "Could not read TRE volume '$TreVolume'; skipping the check."
        return
    }

    if ($count -gt 0) {
        Write-Note "TRE volume '$TreVolume' already holds $count .tre files."
        return
    }

    if (-not (Test-Path -LiteralPath $TrePath)) {
        Write-Warn "Volume '$TreVolume' is empty and TrePath '$TrePath' does not exist."
        Write-Warn 'The server cannot boot without the client .tre files.'
        Write-Warn 'Re-run as: .\core3.ps1 -TrePath "<your client folder>"'
        return
    }

    $hostCount = @(Get-ChildItem -LiteralPath $TrePath -Filter '*.tre' -ErrorAction SilentlyContinue).Count

    if ($hostCount -eq 0) {
        Write-Warn "No .tre files found in '$TrePath'."
        return
    }

    Write-Step "Copying $hostCount .tre files from $TrePath into volume '$TreVolume'..."

    docker run --rm -v "${TreVolume}:/tre" -v "${TrePath}:/tre-src:ro" --entrypoint bash $Image `
        -c 'cp /tre-src/*.tre /tre/ && echo "copied: $(ls -1 /tre/*.tre | wc -l)"'

    if ($LASTEXITCODE -ne 0) { throw 'Failed to populate the TRE volume.' }
}

function Get-ContainerState {
    $state = docker inspect --format '{{.State.Status}}' $Container 2>&1

    if ($LASTEXITCODE -ne 0) { return 'absent' }

    return "$state".Trim()
}

function Start-Core3 {
    $state = Get-ContainerState

    switch ($state) {
        'running' {
            Write-Step "Attaching to $Container (detach without stopping it: Ctrl-P Ctrl-Q)..."
            docker attach $Container
        }
        'absent' {
            Write-Step "Creating $Container..."

            $arguments = @(
                'run', '-it',
                '--name', $Container,
                '--hostname', $Container,
                '--cap-add=SYS_PTRACE',
                '--restart=unless-stopped',
                '-e', 'REPO_LOCAL_PATH=/src',
                '-e', "GALAXY_NAME=$Container",
                '-e', 'GALAXY_ADDRESS=127.0.0.1',
                '-v', "${RepoRoot}:/src:ro",
                '-v', "${HomeVolume}:/home/swgemu",
                '-v', "${TreVolume}:/tre:ro"
            )

            foreach ($port in $PortMap) { $arguments += @('-p', $port) }

            $arguments += $Image

            docker @arguments
        }
        default {
            Write-Step "Starting $Container (was $state)..."
            docker start -ai $Container
        }
    }
}

switch ($Action) {
    'stop' {
        Write-Step "Stopping $Container..."
        docker stop $Container
        return
    }
    'logs' {
        docker logs -f --tail 200 $Container
        return
    }
    'shell' {
        if ((Get-ContainerState) -ne 'running') {
            throw "$Container is not running. Run '.\core3.ps1' first."
        }
        docker exec -it $Container /bin/su - swgemu
        return
    }
    'reset' {
        Write-Warn "This permanently deletes container '$Container' and volume '$HomeVolume':"
        Write-Warn 'the in-container build tree, the MariaDB database, and all characters.'

        if ((Read-Host "Type 'reset' to confirm") -ne 'reset') {
            Write-Host 'Aborted.'
            return
        }

        docker rm -f $Container 2>&1 | Out-Null
        docker volume rm $HomeVolume 2>&1 | Out-Null
    }
}

Initialize-Host
Initialize-Image -Force:($Action -eq 'rebuild')
Initialize-TreVolume

Write-Host ''
Write-Note 'Inside the container:'
Write-Note '  build    compile Core3 (first build is long)'
Write-Note '  run      start the server in a screen session'
Write-Note '  sync     pull new commits from this host checkout'
Write-Note 'Only committed work reaches the container.'
Write-Host ''

Start-Core3
