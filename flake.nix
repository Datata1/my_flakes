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
      export PGPASSWORD=$(${pkgs.openssl}/bin/openssl rand -base64 32)

      mkdir -p "$PGDATA" "$PGLOCKDIR" "$PGSOCKETDIR"

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

      echo "Starting PostgreSQL on port $PGPORT..."
      ${pkgs.postgresql}/bin/postgres -D "$PGDATA" -p "$PGPORT" -k "$PGSOCKETDIR" &

      trap "echo 'Stopping PostgreSQL...'; ${pkgs.postgresql}/bin/pg_ctl -D $PGDATA stop" EXIT

      echo "Waiting for PostgreSQL to start..."
      sleep 2

      echo "PostgreSQL started and password set."
      tail -f /dev/null  
    '';

  in {

    devShell.x86_64-linux = pkgs.mkShell {
      buildInputs = [
        pkgs.postgresql
        pkgs.openssl
      ];
    };

    apps.x86_64-linux.postgres = {
      type = "app";
      program = "${startPostgres}/bin/start-postgres";
    };

    defaultApp.x86_64-linux = self.apps.x86_64-linux.postgres;
  };
}