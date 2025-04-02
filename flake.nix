{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
  let
    pkgs = nixpkgs.legacyPackages.x86_64-linux;

    startPostgres = pkgs.writeShellScriptBin "start-postgres" ''
      export PGDATA=$(pwd)/pgdata
      export PGPORT=5432
      export PGLOCKDIR=$(pwd)/pglockdir
      export PGSOCKETDIR=$(pwd)/pgsocket
      # for dev purposes set default passowrd
      export PGPASSWORD="devpassword"
      # export PGPASSWORD=$(${pkgs.openssl}/bin/openssl rand -base64 32)
      export LANG="C.UTF-8"
      export LC_ALL="C.UTF-8"
      
      mkdir -p "$PGDATA" "$PGLOCKDIR" "$PGSOCKETDIR"

      DB_USER=$(whoami)
      DB_NAME="$DB_USER"

      # --- initdb ---
      if [ ! -f "$PGDATA/PG_VERSION" ]; then
        echo "Initializing database..."
        
        echo "$PGPASSWORD" > password.txt
        ${pkgs.postgresql}/bin/initdb -D "$PGDATA" -U $(whoami) --auth-host=md5 --auth-local=md5 --auth=md5 --pwfile=password.txt
        rm password.txt
        echo "Your generated PostgreSQL password is: $PGPASSWORD"

        if [ ! -f "$PGDATA/PG_VERSION" ]; then
          echo "Error: PostgreSQL database initialization failed. Check initdb.log for details."
          exit 1
        fi
      fi

      # --- PostgreSQL Server starten ---
      echo "Starting PostgreSQL on port $PGPORT..."
      ${pkgs.postgresql}/bin/postgres -D "$PGDATA" -p "$PGPORT" -k "$PGSOCKETDIR" &
      POSTGRES_PID=$! 

      # --- Warten bis Server bereit ist ---
      echo "Waiting for PostgreSQL server to accept connections..."
      MAX_TRIES=15
      COUNT=0
      while ! ${pkgs.postgresql}/bin/pg_isready -h localhost -p $PGPORT -U "$DB_USER" -q; do
        if ! kill -0 $POSTGRES_PID 2>/dev/null; then
          echo "PostgreSQL process $POSTGRES_PID died unexpectedly during startup."
          exit 1
        fi
        sleep 1
        COUNT=$((COUNT + 1))
        if [ $COUNT -ge $MAX_TRIES ]; then
            echo "PostgreSQL server did not become ready in time."
            exit 1
        fi
      done
      echo "PostgreSQL server is ready."

      # --- Anwendungsdatenbank erstellen (falls nicht vorhanden) ---
      echo "Checking/Creating database '$DB_NAME'..."
      ${pkgs.postgresql}/bin/psql -h localhost -p $PGPORT -U "$DB_USER" -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname = '$DB_NAME'" | grep -q 1 || \
        ${pkgs.postgresql}/bin/psql -h localhost -p $PGPORT -U "$DB_USER" -d postgres -c "CREATE DATABASE \"$DB_NAME\";"

      echo "Database '$DB_NAME' is ready for connections."
      echo "PostgreSQL running with PID $POSTGRES_PID. User: $DB_USER, DB: $DB_NAME, Port: $PGPORT"

       # --- TimescaleDB Extension installieren ---
      echo "Installing TimescaleDB extension..."
      ${pkgs.postgresql}/bin/psql -h localhost -p $PGPORT -U "$DB_USER" -d "$DB_NAME" -c "CREATE EXTENSION IF NOT EXISTS timescaledb CASCADE;"

      # --- Auf Beendigung warten & Aufräumen ---
      cleanup() {
          echo "Received signal, stopping PostgreSQL (PID $POSTGRES_PID)..."
          kill -TERM $POSTGRES_PID
          wait $POSTGRES_PID
          echo "PostgreSQL stopped."
      }
      trap cleanup INT TERM EXIT

      wait $POSTGRES_PID
      echo "PostgreSQL process $POSTGRES_PID exited."
    '';

  in {

    devShell.x86_64-linux = pkgs.mkShell {
      buildInputs = [
        pkgs.postgresql
        pkgs.postgresql17Packages.timescaledb
        pkgs.openssl
        pkgs.glibcLocales
      ];
    };

    apps.x86_64-linux.postgres = {
      type = "app";
      program = "${startPostgres}/bin/start-postgres";
    };

    defaultApp.x86_64-linux = self.apps.x86_64-linux.postgres;
  };
}