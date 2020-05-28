# Bitbucket, Traefik & SSL, Postgres - Docker and Docker Compose
This repository demonstrates how to use Atlassian's official [Bitbucket docker image](https://hub.docker.com/r/atlassian/bitbucket-server), The official [PostgreSQL image](https://hub.docker.com/_/postgres) and [Traefik](https://containo.us/traefik/) as a proxy handling SSL certificate management through [LetsEncrypt](https://letsencrypt.org/) with AWS route53.


## Overview
Intended as a simple setup deployed on **one virtual machine (VM)** and orchestrated by docker-compose. Backups can be done with nightly snapshots or scripted. There is a **very simple** backup.sh script which demonstrates how to backup both the file system and the database locally on the machine. You could have CI server execute it and store the backups if wanted. 

![Architectural Overview](bitbucket-docker-overview.png)

Traefik proxies:

* SSH on TCP port 7999
* Traefik Dashboard on port 8080
* Bitbucket on port 443

![Traefik Overview](traefik-overview.png)

## Requirements

* A domain registered in AWS Route53 for domain verification with LetsEncrypt for SSL cert management. Example: `thedukedk.net`.
* AWS Account ID and the corresponding secret.
* Linux Host with Docker and Docker Compose installed. 

## Preparation
* Fill out the variables in the `.env` file.
* Add the FQDN to your hosts file. **Must** match `SERVER_PROXY_NAME` in the `.env` file. Example: `bitbucket.thedukedk.net`.

## Run

`docker-compose up -d`

* Container restart policies are set to `unless-stopped` so they will be restarted on a reboot unless specifically stopped.

## Access
* Traefik Dashboard: http://localhost:8080
* Bitbucket: FQDN. Example: `https://bitbucket.thedukedk.net`.

![Bitbucket](bitbucket.png)

## Backup
Run `./backup-restore.sh -b`.

This will produce **two time stamped** files in a sub-directory called `backup`. 

* `<TIMESTAMP>-bitbucket-db.sql` which is produced by pg_dump.
* `<TIMESTAMP>-bitbucket-data.tgz` which is just compressed tarball of Bitbuckets home directory.
* If the containers were running when the backup was executed they will be restarted. 

## Restore
Run `./backup-restore.sh -r -t backup/<TIMESTAMP>-bitbucket-data.tgz -d backup/<TIMESTAMP>-bitbucket-db.sql`

* A Fresh backup will be done prior to restoring for rollback purposes.
* If the containers were running when the restore was executed they will be restarted.
