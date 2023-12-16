#!/usr/bin/env bash
set -x
set -eo pipefail

if ! [ -x "$(command -v nc)" ]; then
  echo >&2 "Error: nc is not installed."
  exit 1
fi

if ! [ -x "$(command -v sqlx)" ]; then
  echo >&2 "Error: sqlx-cli is not installed."
  echo >&2 "Use:"
  echo >&2 "    cargo install sqlx-cli --no-default-features --feature rustls,postgres"
  echo >&2 "to install it."
  exit 1
fi

# Check if a custom user has been set, otherwise default to 'postgres'
DB_USER=${POSTGRES_USER:=postgres}
DB_PASSWORD=${POSTGRES_PASSWORD:=password}
DB_NAME=${POSTGRES_DB:=newsletter}
DB_PORT=${POSTGRES_PORT:=5432}
DB_HOST=${POSTGRES_HOST:=localhost}

# Allow to skip Docker if a dockerized database is already running
if [[ -z "$SKIP_DOCKER" ]]
then
  #Lauch posgres using Docker
  docker run \
    -e POSTGRES_USER=${DB_USER} \
    -e POSTGRES_PASSWORD=${POSTGRES_PASSWORD} \
    -e POSTGRES_DB=${POSTGRES_DB} \
    -p "${DB_PORT}":5432 \
    -d postgres \
    postgres -N 1000
fi

# Keep pinging Postgres until it's ready to accept commands
until nc -zv $DB_HOST $DB_PORT; do
  >&2 echo "Postgres is still unavailable - sleeping"
  sleep 3
done

>&2 echo "Postgres is up and running on port ${DB_PORT}!"

DATABASE_URL=postgres://${DB_USER}:${DB_PASSWORD}@${DB_HOST}:${DB_PORT}/${DB_NAME}
export DATABASE_URL
sqlx database create
sqlx migrate run

>&2 echo "Postgres has been migrated, ready to go!"

