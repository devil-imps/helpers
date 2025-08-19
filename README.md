# devil Imps Helpers

A collection of shell scripts and utilities for devil servers ([MyDevil.net](https://www.mydevil.net/), [Small.pl](https://www.small.pl/), [hostUNO.com](https://www.hostuno.com/), [Ct8.pl](https://www.ct8.pl/) and [Serv00.com](https://www.serv00.com/)) This repository is organized into several helper tools, each with its own purpose and documentation.

## Helpers

### [Lilith: Devil's Package Manager](lilith/README.md)
Lilith is a self-contained package manager for regular users without root privileges, inspired by FreeBSD's package system. It allows you to install, update, and remove packages in your home directory on devil servers.

### [MySQL Backup Script](mysql-backup/README.md)
Script that automates the backup of MySQL databases on devil servers. It is designed to be run on devil servers, because it use devil2.sock interface!


## Getting Started

1. Enable BinExec
    ```sh
    devil binexec on
    ```

2. Clone the repository:
    ```sh
    git clone https://github.com/devil-imps/helpers.git ~/.helpers
    ```

3. Add bin paths
    ```sh
    cat <<'EOF' >> ~/.bash_profile
    # devil-imps/helpers bin
    export PATH="$HOME/.helpers/bin:$PATH"
    EOF
    source ~/.bash_profile
    ```

4. Review the documentation in each tool's subdirectory for setup and usage instructions.

## Contributing

Contributions, issues, and feature requests are welcome! Feel free to check the issues page or submit a pull request.

## License

This project is licensed under the GNU AFFERO GENERAL PUBLIC LICENSE License. See the [LICENSE](LICENSE) file for details.