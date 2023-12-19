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
  RUNNING_POSTGRES_CONTAINER=$(docker ps --filter 'name=postgres' --format '{{.ID}}')
  if [[ -n  $RUNNING_POSTGRES_CONTAINER ]]; then
    >&2 echo "Docker container with postgres is already running"
    exit 1
  fi
  #Lauch posgres using Docker
  docker run \
    -e POSTGRES_USER=${DB_USER} \
    -e POSTGRES_PASSWORD=${POSTGRES_PASSWORD} \
    -e POSTGRES_DB=${POSTGRES_DB} \
    -p "${DB_PORT}":5432 \
    -d \
    --name "postgres_$(date '+%s')" \
    postgres -N 1000
fi

# Keep pinging Postgres until it's ready to accept commands
test_connection="nc -zv $DB_HOST $DB_PORT"

# Number of attempts
attempts=5

# Loop to try the command multiple times
for ((i=1; i<=$attempts; i++)); do
    echo "Attempt $i:"
    $test_connection

    # Check the exit status of the command
    if [ $? -eq 0 ]; then
       >&2 echo "Command executed successfully."
       >&2 echo "Postgres is up and running on port ${DB_PORT}!"
        break  # Exit the loop if the command succeeds
    else
        echo "Command failed. Retrying..."
    fi

    # Add a delay between attempts (optional)
    sleep 3
done


DATABASE_URL=postgres://${DB_USER}:${DB_PASSWORD}@${DB_HOST}:${DB_PORT}/${DB_NAME}
export DATABASE_URL
sqlx database create
sqlx migrate run

>&2 echo "Postgres has been migrated, ready to go!"

