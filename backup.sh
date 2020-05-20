#!/bin/sh

DATE=$(date +"%d%m%y%y_%H%M%S")

WAS_RUNNING=$(docker ps | awk '{print $NF}' | grep -E "^bitbucket$" | cat)

if [ "${WAS_RUNNING}" ]; then
    echo "Stopping Bitbucket during backup..."
    docker-compose -f bitbucket-compose.yml stop > /dev/null 2>&1
fi

echo "Backing up Bitbucket data directory..."
docker run --name data_backup -v bitbucket_data:/bitbucket_data \
-v $(pwd):/backup alpine \
sh -c "cd bitbucket_data && tar czfv /backup/${DATE}-bitbucket.tar.gz ." > /dev/null 2>&1
docker rm data_backup > /dev/null 2>&1

echo "Running pg_dump with only database running..."
docker-compose -f postgres-compose.yml up -d > /dev/null 2>&1
docker exec postgres-bitbucket sh -c "pg_dump -U bitbucket --dbname=bitbucket" > ${DATE}-bitbucket.sql
docker-compose -f postgres-compose.yml stop > /dev/null 2>&1

if [ "${WAS_RUNNING}" ]; then
    echo "Bringing Bitbucket and Database back up in same context..."
    docker-compose -f postgres-compose.yml -f bitbucket-compose.yml up -d
fi
