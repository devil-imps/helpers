# Lilith: Devil's Package Manager

Lilith is a self-contained package manager for regular users without root privileges, inspired by FreeBSD's package system. It allows you to install, update, and remove packages in your home directory on devil servers ([MyDevil.net](https://www.mydevil.net/), [Small.pl](https://www.small.pl/), [hostUNO.com](https://www.hostuno.com/), [Ct8.pl](https://www.ct8.pl/) and [Serv00.com](https://www.serv00.com/)).

## Features
- Installs packages in `~/.lilith` (no root required), ideal for devil server!
- Downloads and extracts FreeBSD packages
- Handles dependencies
- Keeps track of installed packages
- Colored output for info, success, warnings, and errors

## Installation
1. Global Helpers Setup

    Before proceeding, please follow the instructions in the [Getting Started](../README.md#getting-started) section of the main [README.md](../README.md) to install helpers.

2. Add Lilith Paths
    ```sh
    cat <<'EOF' >> ~/.bash_profile
    # lilith paths
    export PATH="$HOME/.lilith/bin:$HOME/.lilith/sbin:$PATH"
    export LD_LIBRARY_PATH="$HOME/.lilith/lib:$LD_LIBRARY_PATH"
    export MANPATH="$HOME/.lilith/share/man:$MANPATH"
    export C_INCLUDE_PATH="$HOME/.lilith/include:$C_INCLUDE_PATH"
    export CPLUS_INCLUDE_PATH="$HOME/.lilith/include:$CPLUS_INCLUDE_PATH"
    export PKG_CONFIG_PATH="$HOME/.lilith/lib/pkgconfig:$HOME/.lilith/libdata/pkgconfig:$PKG_CONFIG_PATH"
    EOF
    source ~/.bash_profile
    ```

**Note:** Lilith automatically creates symlinks in `~/.lilith/lib/` for any shared libraries found in subdirectories, so you only need the simple `LD_LIBRARY_PATH` setup above.

3. Run Lilith Commands
    ```sh
    lilith <command> [options] <package_name>
    ```

## Commands
```text
Lilith: Devil's Package Manager
A self-contained package manager for regular users without root privileges

USAGE:
    lilith <command> [arguments]

COMMANDS:
    install [options] <package>   Install a package and its dependencies
                                  Options: --full-deps (install all dependencies)
                                           --no-deps (skip dependencies)
    update <package>              Update a package to the latest version
    remove [options] <package>    Remove a package from the system
                                  Options: --force (remove even if required by others)
                                           --no-auto-remove (keep orphaned dependencies)
    search [options] <query>      Search for packages matching the query
                                  Options: -a/--all (search names and descriptions)
    info <package>                Show detailed information about a package
    list                          List all installed packages
    update-metadata               Update package repository metadata
    fix-symlinks                  Create symlinks for libraries in subdirectories
    help                          Show this help message
```

## How It Works
- Packages are downloaded from the FreeBSD repository based on your system's ABI
- Extracted files are placed in `~/.lilith` directories (bin, lib, etc.)
- Metadata and manifests are stored for tracking and removal

## Troubleshooting
- If you see errors about missing tools, install them using your system's package manager
- For metadata issues, run `lilith update-metadata`

---
For more details, see comments in `lilith.sh`.
