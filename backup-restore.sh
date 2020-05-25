#!/bin/sh

set -euo pipefail

BACKUP=0
RESTORE=0
TAR=""
DB=""
RESTART=0

# Usage info
show_help() {
cat << EOF
Usage: ${0##*/} [-h] [-r|-b backup or restore. Mutually exclusive.] [-d db-backup.bin file] [-t data-backup.tgz]...
  
  -h                Display this help and exit 0.
  -b                A backup operation.
  -r                A restore operation. 
  -d <NAME>         The database .bin file to restore.
  -t <NAME>         The file system .tgz file to restore.

EOF
}

backup() {
    DATE=$(date +"%d%m%y%y_%H%M%S")
    local RUNNING=$(docker ps | awk '{print $NF}' | grep -E "^bitbucket$" | cat)

    if [ "${RUNNING}" ]; then
        RESTART=1
        echo "Stopping Bitbucket during backup..."
        docker-compose down --timeout 90 > /dev/null 2>&1
    fi

    docker-compose -f backup-restore-compose.yml up -d > /dev/null 2>&1
    echo "Backing up Bitbucket data directory..."
    docker exec backup-bitbucket sh -c "cd /bitbucket_data && mkdir -p /host/backup/ && tar czf /host/backup/${DATE}-bitbucket-data.tgz ."
    echo "Backing up database with pg_dump..."
    docker exec backup-bitbucket sh -c "pg_dump --username bitbucket --format=p --dbname=bitbucket --file=/host/backup/${DATE}-bitbucket-db.sql"
    docker-compose -f backup-restore-compose.yml down --timeout 30 > /dev/null 2>&1

    # If it was running AND this is a BACKUP operation bring it back to previous state. 
    # Otherwise bring it back to previous state after RESTORE operation.
    if [[ "${RESTART}" == 1 && "${BACKUP}" == 1 ]]; then
        docker-compose up -d > /dev/null 2>&1
    fi
}

restore() {
    backup # Make a fresh backup in case things go wrong.

    docker-compose -f backup-restore-compose.yml up -d > /dev/null 2>&1
    if [ "${DB}" ]; then
        echo "Restoring database with ${DB}"
        docker exec -it backup-bitbucket sh -c "psql -U bitbucket -d bitbucket < /host/backup/${DB}"
    fi
    if [ "${TAR}" ]; then
        echo "Restoring data directory with ${TAR}"
        docker exec -it backup-bitbucket sh -c "tar -xzf /host/backup/${TAR} --directory /bitbucket_data"
    fi
    docker-compose -f backup-restore-compose.yml down > /dev/null 2>&1

    if [[ $RESTART == 1 ]]; then
        docker-compose up -d /dev/null 2>&1
    fi
}

OPTIND=1

while getopts 'd:t:rbh' opt; do
    case $opt in
        h)
            show_help
            exit 0
        ;;
        b)
            BACKUP=1
        ;;
        r)
            RESTORE=1
        ;;
        d)
            if [ ! -f "${OPTARG}" ]; then
                echo "The file ${OPTARG} does not seem to exist! Exiting..."
                exit 1
            elif [ ! "${OPTARG##*.}" == "sql" ]; then
                echo "This doesn't look like a .sql file! Exiting..."
                exit 1
            fi
            DB="${OPTARG##*/}"
        ;;
        t)
            if [ ! -f "${OPTARG}" ]; then
                echo "The file ${OPTARG} does not seem to exist! Exiting..."
                exit 1
            elif [ ! "${OPTARG##*.}" == "tgz" ]; then
                echo "This doesn't look like a zipped .tgz! Exiting..."
                exit 1
            fi
            TAR="${OPTARG##*/}"
        ;;
        \?)
            show_help
            exit 1
            ;;
    esac
done
shift "$((OPTIND-1))"   # Discard the options and sentinel --

if [[ $RESTORE == 1 && $BACKUP == 1 ]]; then
    echo "You can only specify -b OR -r"
    show_help
    exit 1
elif [[ $RESTORE == 1 && ( ! $TAR && ! $DB ) ]]; then
    echo "You must provide something to restore! Exiting..."
    show_help
    exit 1
fi

if [ $RESTORE == 1 ]; then
    # User confirmation
    echo "-----------------------------------------------------"
    if [[ ! "${DB}" || ! "${TAR}" ]]; then
        read -p "This looks like a partial restore! Are you SURE?
        Database SQL file: ${DB} 
        Data directory .tgz file: ${TAR}

        A fresh BACKUP will be done prior to a restore.
        [Y|y]:[N|n] : " ANSWER
    else
        read -p "Restore the following. 
        Database SQL file: ${DB} 
        Data directory .tgz file: ${TAR}

        A fresh BACKUP will be done prior to a restore.
        [Y|y]:[N|n] : " ANSWER
    fi
    echo "-----------------------------------------------------"
    case $ANSWER in
        Y|y)
            restore
        ;;
        N|n)
            exit 0
        ;;
        *)
            echo "You must answer [Y|y] or [N|n]."
            exit 1
        ;;
    esac
else
    backup
fi