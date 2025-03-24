{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
  let
    pkgs = nixpkgs.legacyPackages.x86_64-linux;

    startPostgres = pkgs.writeShellScriptBin "start-postgres" ''
      export PGDATA=$(pwd)/pgdata
      export PGHOST="localhost"
      export PGPORT=5432
      export PGLOCKDIR=$(pwd)/pglockdir
      export PGSOCKETDIR=$(pwd)/pgsocket
      export PGPASSWORD=$(${pkgs.openssl}/bin/openssl rand -base64 32)
      export LANG="C.UTF-8"
      export LC_ALL="C.UTF-8"

      # Verzeichnisse erstellen
      mkdir -p "$PGDATA" "$PGLOCKDIR" "$PGSOCKETDIR"

      # Setze die richtigen Berechtigungen
      chmod 700 "$PGDATA"
      chmod 700 "$PGLOCKDIR"
      chmod 700 "$PGSOCKETDIR"
      
      # Setze den Besitzer der Verzeichnisse auf den aktuellen Benutzer
      chown "$(whoami):$(id -gn)" "$PGDATA" "$PGLOCKDIR" "$PGSOCKETDIR"

      # Überprüfen, ob die Datenbank bereits initialisiert wurde
      if [ ! -f "$PGDATA/PG_VERSION" ]; then
        echo "Initializing database..."
        
        # Logge die Ausgabe von initdb, um Fehler zu erkennen
        echo "$PGPASSWORD" > password.txt
        ${pkgs.postgresql}/bin/initdb -D "$PGDATA" -U $(whoami) --auth-host=md5 --auth-local=md5 --auth=md5 --pwfile=password.txt
        echo "password is $(cat password.txt)"
        rm password.txt
        echo "Your generated PostgreSQL password is: $PGPASSWORD"

        # Überprüfen, ob die Initialisierung erfolgreich war
        if [ ! -f "$PGDATA/PG_VERSION" ]; then
          echo "Error: PostgreSQL database initialization failed. Check initdb.log for details."
          exit 1
        fi
      fi

      echo "Starting PostgreSQL on port $PGPORT..."
      ${pkgs.postgresql}/bin/postgres -D "$PGDATA" -p "$PGPORT" -k "$PGSOCKETDIR" &

      trap "echo 'Stopping PostgreSQL...'; ${pkgs.postgresql}/bin/pg_ctl -D $PGDATA stop" EXIT

      # Warten, bis PostgreSQL vollständig gestartet ist
      echo "Waiting for PostgreSQL to start..."
      sleep 3

      echo "PostgreSQL started and password set."
      tail -f /dev/null  # Warten, damit die Shell offen bleibt
    '';

  in {

    devShell.x86_64-linux = pkgs.mkShell {
      buildInputs = [
        pkgs.postgresql
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