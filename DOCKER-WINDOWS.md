# Core3 in Docker on Windows

Run the full Core3 build and server in a container. No WSL instance to set up:
Docker Desktop's WSL2 backend uses its own auto-managed distro.

## Requirements

- Docker Desktop for Windows
- A Star Wars Galaxies client folder containing the `.tre` files
- ~40GB free disk, and RAM to spare (the script asks the VM for 16GB)

## Run it

```powershell
cd docker
.\core3.ps1
```

If your client is not at `C:\Programs\SWGEmu`:

```powershell
.\core3.ps1 -TrePath "C:\path\to\SWGEmu"
```

One command does everything: starts Docker Desktop, sizes the VM, builds the
image, copies the `.tre` files into the `shared-tre` volume, creates the
container, and attaches you to its shell.

Then, inside the container:

```
build     # compile Core3 -- about 7 minutes on 16 cores, only needed once
run       # start the server under gdb in a screen session
```

The server is ready when the console prints `READY` and a `>` prompt. First
boot takes about a minute. Detach from the screen session with `Ctrl-A D`,
leaving the server running.

### First run timings

| Step | Time |
| --- | --- |
| Image build | 15-30 minutes (clang toolchain and dependencies) |
| TRE copy | about 30 seconds for 53 files |
| Container firstboot | about 1 minute (clone, submodules, database) |
| `build` | about 7 minutes on 16 cores |
| Server boot to `READY` | about 1 minute |

Only `run` is needed on later starts.

## Verify it is up

From PowerShell:

```powershell
(New-Object Net.Sockets.TcpClient('127.0.0.1',44455)).Connected
```

`True` means the server is listening. For uptime and player count:

```powershell
$c=New-Object Net.Sockets.TcpClient('127.0.0.1',44455);$s=$c.GetStream();$s.ReadTimeout=8000
$b=New-Object byte[] 2048;$n=$s.Read($b,0,$b.Length)
[Text.Encoding]::ASCII.GetString($b,0,$n);$c.Close()
```

Do not use `pgrep core3` inside the container to check this. `pgrep` matches
zombie processes, so a crashed server can still look alive. Use `screen -ls`,
or `ps -o stat= -p $(pgrep -x core3)` and treat `Z` as not running.

To point a client at the server, set `loginServerAddress0=127.0.0.1` in the
client's `swgemu_login.cfg`. Auto-registration is on, so the first
username and password you type creates that account.

## Script actions

```powershell
.\core3.ps1            # start and attach (default)
.\core3.ps1 shell      # extra shell in the running container
.\core3.ps1 stop       # stop the container
.\core3.ps1 logs       # tail container output
.\core3.ps1 rebuild    # rebuild the image, then start
.\core3.ps1 reset      # delete the container and its home volume, start fresh
```

`reset` discards the in-container build tree, the database, and all characters.
It prompts for confirmation and keeps the TRE volume.

Other flags: `-MemoryGB`, `-Processors`, `-SkipHostConfig` (leave
`%USERPROFILE%\.wslconfig` alone).

## Pushing changes into a running container

The container does **not** build from your working tree. It builds from a git
clone made inside the container, for two reasons:

- This repository is normally checked out with `core.autocrlf=true`, so the
  Windows working tree has CRLF line endings that will not compile under Linux.
  Cloning re-checks-out the tree inside the container with LF endings.
- Build output stays on a Linux-native Docker volume instead of crossing the
  host filesystem boundary, which is much faster.

**The consequence: only committed work reaches the container.**

### C++ or Lua source changes

1. Commit on the host:
   ```powershell
   git add -A
   git commit -m "your change"
   ```
2. Inside the container, pull the new commits:
   ```
   sync
   ```
3. Rebuild and restart:
   ```
   build
   run
   ```

`sync` fast-forwards the container's clone from the host checkout (git remote
`local`, a read-only bind mount at `/src`) and refreshes submodules. It refuses
to merge anything but a fast-forward, so rebase or amend on the host rather than
forcing history into the container.

`build` is incremental, so a one-file change takes far less than the initial
7 minutes.

### Lua script changes without a restart

Screenplay and script changes do not need a rebuild. At the server console:

```
reloadscreenplays
```

### Dockerfile or firstboot changes

Changes to `docker/Dockerfile`, `docker/files/`, or the helper scripts live in
the image, not the clone:

```powershell
.\core3.ps1 rebuild
```

A rebuilt image does not alter the existing container. To pick up firstboot
changes such as `docker/files/firstboot/functions`, you need a fresh container
and home volume:

```powershell
.\core3.ps1 reset
```

That re-runs firstboot against the new image, and costs a full `build` again.

## Restarting the server

Attach to the console and shut down cleanly:

```powershell
docker exec -it swgemu-core3 su - swgemu -c 'screen -D -RR swgemu-server'
```

At the `>` prompt:

```
shutdown 0
```

The argument is required; bare `shutdown` only prints usage. Use `0` for
immediate or `5` to warn players first. When gdb returns to its `(gdb)` prompt,
type `quit`, then `run` to start again.

Do not pass `fast` or `json` alongside the number. `UnsignedInteger::valueOf` is
called on the whole argument string, so `shutdown 0 fast` fails to parse and only
prints the usage line -- the usage text advertises a combination the parser does
not accept.

Other useful console commands: `save` (flush to disk without stopping), `info`
(server state), `help` (full list).

For a hard restart that also clears a zombie process:

```powershell
docker restart swgemu-core3
```

This kills the server mid-flight, so prefer `shutdown 0` when world state
matters.

## Ports

| Port | Protocol | Purpose |
| --- | --- | --- |
| 44453 | udp | login |
| 44455 | tcp | status |
| 44462 | udp | ping |
| 44463 | udp | zone |
| 2222 | tcp | ssh |

All are published to the Windows host. The REST API is off by default; see
[MMOCoreORB/src/server/web/README.md](MMOCoreORB/src/server/web/README.md) to
enable it, and add its port to `$PortMap` in `docker/core3.ps1`.

## Memory and CPU

Under the WSL2 backend, Docker Desktop's Resources memory slider does nothing.
The VM's memory comes from `%USERPROFILE%\.wslconfig`, which `core3.ps1`
manages:

```ini
[wsl2]
memory=16GB
processors=16
swap=16GB
```

`processors=16` is deliberate. `build` parallelizes on `nproc`, and 32
concurrent clang jobs will exhaust 16GB. If you raise `-Processors`, raise
`-MemoryGB` with it.

Changing these requires the VM to restart; `core3.ps1` handles that when it
detects a change. On the Hyper-V backend `.wslconfig` does not apply, and the
script says so -- set memory under Settings > Resources instead.

## Troubleshooting

**`** Already running **` when you type `run`.** A zombie `core3` process is
confusing the check in `~/bin/run`. Confirm with `screen -ls`; if no socket is
listed, the server is not running. Fix with `docker restart swgemu-core3`.

**`build` fails instantly.** It runs `clear` under `#!/bin/bash -xe`, so it
needs a TTY. Run it from an interactive shell, not `docker exec` without `-t`.

**Client reports "login server not available".** The client is pointing
somewhere else. Check `loginServerAddress0` in `swgemu_login.cfg`.

**`sync` reports no `local` remote.** The container was created without
`REPO_LOCAL_PATH`, so it cloned from GitHub instead of your checkout. Recreate
it with `.\core3.ps1 reset`.

**Your commits are not in the container.** Run `sync`. If it says "Already up
to date", you have not committed on the host yet.
