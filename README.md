# SWGEmu Core3: Recreating the Classic Star Wars Galaxies Experience

## What is SWGEmu?

Star Wars Galaxies (SWG) was an immensely popular massively multiplayer online role-playing game (MMORPG) introduced by Sony Online Entertainment in 2003. Despite its eventual shutdown in 2011, SWG left a lasting legacy in the hearts of thousands of players.

The SWGEmu project aims to recapture the magic of the game by focusing on a specific milestone: Pre-CU, or Pre-Combat Upgrade. The Combat Upgrade introduced significant changes to the gameplay, which were met with disapproval by many devoted players. It was in response to these changes that the SWGEmu project was born—a collective effort to "recreate" the game as it existed during the Pre-CU era.

At the core of the SWGEmu project lies the "Emulator," referring to the meticulously crafted server software being developed by the SWGEmu team. This Emulator endeavors to faithfully mimic Sony Online Entertainment's server-side software, which once hosted the immersive galaxies of Star Wars Galaxies during the Pre-CU era. To achieve this ambitious goal, the SWGEmu team has dedicated countless hours to reverse-engineering the code from scratch. They have built their own custom engine and core game logic, ensuring that every detail is crafted with love and precision.

The SWGEmu project is not only a nostalgic journey for passionate players but also a testament to the dedication and perseverance of a talented team. By resurrecting the Pre-CU era, SWGEmu offers an opportunity for both veterans and newcomers to experience the rich and captivating universe of Star Wars Galaxies, as it was once cherished by thousands of fans.

If you have any questions, need support, or want to contribute to the SWGEmu project, please refer to the documentation and resources provided in this repository.

## Docker Build

If you have docker (i.e. Linux docker daemon, Windows/MacOS [Docker Desktop](https://www.docker.com/products/docker-desktop/)) you can run the entire development environment and server in a container.

### Windows quick start (no WSL setup required)

Full Windows guide, including how to push changes into a running container:
[DOCKER-WINDOWS.md](DOCKER-WINDOWS.md).

Docker Desktop's WSL2 backend runs in its own auto-managed distro, so you do not
need to install or configure a WSL instance of your own. From PowerShell:

```
cd docker
.\core3.ps1
```

That single command starts Docker Desktop if it is not running, sets the Docker
VM to 16GB RAM and 16 CPUs, builds the image, copies your client `.tre` files
into the `shared-tre` volume, then creates the container and drops you into its
shell. Point it at your client with `-TrePath "C:\path\to\SWGEmu"` if the default
(`C:\Programs\SWGEmu`) is wrong, and change the VM sizing with `-MemoryGB` /
`-Processors`.

Other actions: `.\core3.ps1 shell` (extra shell in the running container),
`stop`, `logs`, `rebuild` (rebuild the image), `reset` (discard the container's
build tree and database and start over).

The container builds from a git clone of your checkout made *inside* the
container rather than from a bind mount, because a Windows working tree with
`core.autocrlf=true` has CRLF line endings that will not build under Linux, and
because keeping build output on a Linux-native volume is far faster. The
consequence is that **only committed work reaches the container** — commit on the
host, then run `sync` inside the container to fast-forward its tree.

If Docker Desktop is on the Hyper-V backend instead, `.wslconfig` does not apply;
set memory under Settings > Resources and the script will tell you so.

### Setup

The docker build creates a container that includes everything needed to run the core3 engine except you need the tre files from the client.

The setup assumes you've copied your tre files to the docker volume 'shared-tre' and in the container they're mounted in /tre/

On linux or macos you can easily create this volume by doing:

```
$ cd ~/SWGEmu
$ tar cf - *.tre | docker run -i --rm -v shared-tre:/tre debian:bullseye bash -c 'tar xvf - -C /tre'
bottom.tre
...
patch_sku1_14_00.tre
```

The docker container will use these files for your server in the container.

### Build

To build the container:

```
cd docker
./build.sh
```

### Develop/Run

Run the container with:

```
cd docker
./run.sh
```

This runs the container and starts and interactive shell, in there you can work with the code (workspace/Core3), build and run the server.

The first time you run the container it will setup the environment and defaults for the server, watch for it to tell you the mysql and admin passwords!

When you're in the container you should have a ~/.my.cnf setup which allows you to easily talk to the mysql sever with the mysql command line client.

All the local configuration is in workspace/Core3/MMOCoreORB/bin/conf/config-local.lua

#### Compile the server

Inside the container type:

```
build
```

#### Run the server

Inside the container type:

```
run
```

#### Pull in new host commits

If the container was created from a local checkout (the Windows quick start
above, or any run with `REPO_LOCAL_PATH` set), commit on the host and then, inside
the container, type:

```
sync
```

## Windows Subsystem for Linux Setup

There is an automated setup available for Windows 10+ with WSL.

See [wsl2/README.md](wsl2/README.md) for instructions.

## Linux Automated Setup

You can use the automated linux setup if you plan to run the server in a vm or dedicated cloud or metal server.

See [linux/README.md](linux/README.md) for instructions.

## Linux Manual Build

### Dependencies
  * Debian 12
  * CMake 3.18.0+
  * BerkeleyDB 5.3
  * MariaDb Client and Server
  * OpenSSL libraries
  * pthreads
  * Lua 5.3 libraries
  * Zlib libraries
  * clang19
  * java runtime
  * boost
  * ninja-build

#### Clang-19

The easiest way to get the clang19 to build with is to use the script provided by the llvm repo:

```
sudo -i
apt-get install -y apt-transport-https ca-certificates git gnupg lsb-release moreutils software-properties-common wget
wget -O /tmp/llvm.sh https://apt.llvm.org/llvm.sh
chmod +x /tmp/llvm.sh
/tmp/llvm.sh 19 all
(set +x;cd /usr/bin;for i in ../lib/llvm-*/bin/*; do ln -sfv $i .; done)
clang --version
ld.lld --version
exit
```

This will install the latest and symlink all the files to /usr/bin so CMake finds them etc.

### Build

  * Install dependencies (Debian 12)

        sudo apt install build-essential libmariadb-dev libmariadb-dev-compat liblua5.3-dev libdb5.3-dev libssl-dev cmake git default-jre libboost-all-dev gdb ninja-build libjemalloc-dev

  * Clone core3 repository somewhere  (~/workspace)

        mkdir -p ~/workspace
        cd ~/workspace
        git clone https://review.swgemu.com/Core3

  * Build Core3 For Development

        cd Core3/MMOCoreORB
        make build-ninja-debug

  * Build Core3 For Production

        cd Core3/MMOCoreORB
        make -j$(nproc)

  * Import sql database into mariadb

        sudo apt-get install mariadb-server
        Setup MariaDB User, database and import sql/swgemu.sql

### How to Run

    * Navigate to the Directory

        cd ~/workspace/Core3/MMOCoreORB/bin

    * Load GDB

        gdb ./core3

    * Start Core3

        r

# License

    Copyright (C) 2019 SWGEmu

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU Affero General Public License as published by the Free Software Foundation,
    either version 3 of the License, or (at your option) any later version.

    This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
    without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
    See the GNU Affero General Public License for more details.

    You should have received a copy of the GNU Affero General Public License along with this program.
    If not, see <http://www.gnu.org/licenses/>.

For more information, see [https://review.swgemu.com/](https://www.docker.com/products/docker-desktop/) or our official [Development Discussion](https://www.swgemu.com/forums/forumdisplay.php?f=10) forums.

# Donate

The SWGEmu project is a 100% volunteer effort and funded by community donations. Consider [donating](https://www.swgemu.com/donate/?rm) to help keep the project moving forward. We use the donations to pay for our infrastructure and services to support the development process and running test servers.
