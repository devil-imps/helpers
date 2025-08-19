# MySQL Backup Script

Script that automates the backup of MySQL databases on devil servers ([MyDevil.net](https://www.mydevil.net/), [Small.pl](https://www.small.pl/), [hostUNO.com](https://www.hostuno.com/), [Ct8.pl](https://www.ct8.pl/) and [Serv00.com](https://www.serv00.com/)). It is designed to be run on devil servers, because it use devil2.sock interface!

## Features
- Creates a backup directory if it does not exist
- Reads MySQL credentials from `.my.cnf` in the script directory
- Enumerates all databases using devil2.sock
- Grants backup privileges to the backup user
- Fetches user databases
- Backs up and compresses each database into `.sql.gz` files
- Revokes backup privileges after backup (that's why the best idea is to create a dedicated backup user for example mXXXX_backups)

## Installation
1. Global Helpers Setup

    Before proceeding, please follow the instructions in the [Getting Started](../README.md#getting-started) section of the main [README.md](../README.md) to install helpers.

2. Create a MySQL backup user
    ```sh
    # Generate a random password any copy it
    openssl rand -base64 20 | tr -dc 'a-zA-Z0-9'

    # Create a backups MySQL user, you can use generate password
    devil mysql user add backups
    ```

3. Prepare `.my.cnf` file
    ```sh
    # Copy example file
    cp ~/.helpers/mysql-backup/.my.cnf-example ~/.helpers/mysql-backup/.my.cnf

    # Edit file and fill all fields with your server data
    nano ~/.helpers/mysql-backup/.my.cnf
    ```

4. Add script to crontab
    ```sh
    (crontab -l 2>/dev/null; echo "15 0 * * * $HOME/.helpers/mysql-backup/backup.sh # MySQL Backup (devil-imps/helpers)") | crontab -
    ```

Backups will be saved in `~/backups-mysql/` as compressed `.sql.gz` files.

## Example .my.cnf
```
[client]
host = mysqlX.mydevil.net
user = mXXXX_backups
password = STRONG_PASSWORD_HERE
```

## Troubleshooting
- If you see errors about missing `.my.cnf`, ensure it is present in the script directory.
- If no databases are found, check your credentials and privileges.
