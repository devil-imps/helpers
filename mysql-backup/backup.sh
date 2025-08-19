#!/bin/bash

#
# MySQL Database Backup Script
# This script automates the backup of MySQL databases on devil servers.
#

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# Set the backup directory (can be changed as needed)
BACKUP_DIR="$HOME/backups-mysql"

# Create backup directory if it doesn't exist
if [ ! -d "$BACKUP_DIR" ]; then
    mkdir -p "$BACKUP_DIR"
    echo "Created backup directory: $BACKUP_DIR"
fi

# Read MySQL username from .my.cnf in the script directory
if [ -f "$SCRIPT_DIR/.my.cnf" ]; then
    MYSQL_USER=$(grep -i '^user' "$SCRIPT_DIR/.my.cnf" | head -n1 | awk -F= '{gsub(/ /, "", $2); print $2}')
else
    echo "Error: $SCRIPT_DIR/.my.cnf not found."
    exit 1
fi

# Enumerate all databases using devil2.sock (custom server socket)
echo "Enumerating all databases using devil2.sock..."
DB_LIST_JSON=$(echo "['--json', 'mysql', 'list']" | nc -U /var/run/devil2.sock)
DB_NAMES=$(echo "$DB_LIST_JSON" | jq -r '[.databases[].Db] | unique[]')

# Grant backup privileges to the backup user for each database
for DB in $DB_NAMES; do
    echo "Setting privileges for $MYSQL_USER on $DB..."
    PRIV_JSON=$(echo "['--json', 'mysql', 'privileges', '$MYSQL_USER', '$DB', '+SELECT', '+SHOW_VIEW', '+LOCK_TABLES']" | nc -U /var/run/devil2.sock)
    echo "Privilege response for $DB: $PRIV_JSON"
done

# Fetch user databases using credentials from .my.cnf
echo "Fetching database list using credentials from $SCRIPT_DIR/.my.cnf..."
DATABASES=$(mysql --defaults-file="$SCRIPT_DIR/.my.cnf" -e "SHOW DATABASES;" | grep -Ev "(Database|information_schema|performance_schema|mysql|sys)")

# Exit if no user databases are found
if [ -z "$DATABASES" ]; then
    echo "Error: Could not retrieve a list of databases or no user databases were found. Check your $SCRIPT_DIR/.my.cnf file."
    exit 1
fi

# Backup and compress each user database
echo "Starting database backup..."
for DB_NAME in $DATABASES; do
    echo "  > Backing up and compressing database: $DB_NAME"
    # Use mysqldump to export, then gzip to compress
    if mysqldump --defaults-file="$SCRIPT_DIR/.my.cnf" --databases "$DB_NAME" --no-tablespaces --routines | gzip >"$BACKUP_DIR/$DB_NAME.sql.gz"; then
        echo "    - Success: Compressed backup for $DB_NAME saved to $BACKUP_DIR/$DB_NAME.sql.gz"
    else
        echo "    - Failed: Could not back up database $DB_NAME."
    fi
done

# Revoke backup privileges from the backup user for each database
for DB in $DB_NAMES; do
    echo "Revoking privileges for $MYSQL_USER on $DB..."
    PRIV_JSON=$(echo "['--json', 'mysql', 'privileges', '$MYSQL_USER', '$DB', '-ALL']" | nc -U /var/run/devil2.sock)
    echo "Privilege response for $DB: $PRIV_JSON"
done
