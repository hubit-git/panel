#!/usr/bin/env bash
# Installs the panel on a server with Docker. Needs a domain that already points to this server.
#
#   bash <(curl -fsSL https://raw.githubusercontent.com/hubit-git/panel/main/install.sh)
#
# Without a terminal (or to skip the question) give the domain in the environment: DOMAIN=panel.example.com bash install.sh
# Run it again on the same server and it keeps the passwords and the data, only the files and containers are renewed.
set -euo pipefail

APP_DIR="${APP_DIR:-/opt/hubit-panel}"
BASE_URL="${BASE_URL:-https://raw.githubusercontent.com/hubit-git/panel/main}"
HTTP_PORT="${HTTP_PORT:-80}"
HTTPS_PORT="${HTTPS_PORT:-443}"

say()  { printf '\n\033[1;34m%s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m%s\033[0m\n' "$*"; }
fail() { printf '\033[1;31m%s\033[0m\n' "$*" >&2; exit 1; }

# Whether there is a terminal to ask on (also when the script itself comes from a pipe)
has_tty() {
    (: < /dev/tty) 2> /dev/null
}

# Asks a question on the terminal; the answer is empty when there is none
ask() {
    local answer=""
    if has_tty; then
        read -r -p "$1" answer < /dev/tty || true
    fi
    printf '%s' "$answer"
}

# The server's public address, to compare with what the domain points to
public_ip() {
    curl -4 -fsS --max-time 5 https://api.ipify.org 2> /dev/null || curl -4 -fsS --max-time 5 https://ifconfig.me 2> /dev/null || true
}

command -v curl > /dev/null || fail "curl is needed: install it first (apt install curl)."

# ---- Docker ----
if ! command -v docker > /dev/null; then
    [ "$(id -u)" -eq 0 ] || fail "Docker is not installed. Run this as root (or with sudo) so it can be installed."
    say "Installing Docker..."
    curl -fsSL https://get.docker.com | sh
fi

docker compose version > /dev/null 2>&1 || fail "Docker Compose is missing. Install the docker-compose-plugin package and run this again."

# ---- Files ----
mkdir -p "$APP_DIR" 2> /dev/null || fail "Cannot create $APP_DIR: run this as root (or with sudo)."
cd "$APP_DIR"

if [ -f .env ]; then
    warn "Found an earlier install in $APP_DIR: keeping its .env (domain and passwords)."
else
    # ---- The domain ----
    domain="${DOMAIN:-}"
    if [ -z "$domain" ]; then
        domain=$(ask "Domain of the panel (for example panel.example.com): ")
    fi

    domain=$(printf '%s' "$domain" | tr 'A-Z' 'a-z' | sed -e 's#^https\?://##' -e 's#/.*$##' -e 's/[[:space:]]//g')
    [ -n "$domain" ] || fail "A domain is needed (the certificate is made for it)."
    printf '%s' "$domain" | grep -Eq '^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*$' || fail "This is not a valid domain: $domain"

    # The certificate is only issued when the domain points here
    server_ip=$(public_ip)
    domain_ip=$(getent ahostsv4 "$domain" 2> /dev/null | awk 'NR==1 {print $1}' || true)
    if [ -n "$server_ip" ] && [ "$domain_ip" != "$server_ip" ]; then
        warn "$domain points to '${domain_ip:-nothing}', but this server is $server_ip. HTTPS will not work until the A record is fixed."
        if has_tty; then
            go=$(ask "Continue anyway? [y/N] ")
            case "$go" in
                y | Y) ;;
                *) fail "Stopped. Point the domain to $server_ip and run this again." ;;
            esac
        fi
    fi

    umask 077
    cat > .env << ENV
DOMAIN=$domain
DB_PASSWORD=$(openssl rand -hex 16)
DB_ROOT_PASSWORD=$(openssl rand -hex 16)
HTTP_PORT=$HTTP_PORT
HTTPS_PORT=$HTTPS_PORT
ENV
    umask 022
fi

# Docker Compose reads these when the stack is started
set -a
. ./.env
set +a

# The ports must be free for Caddy (on a second run they are ours)
if [ -z "$(docker compose ps --quiet 2> /dev/null)" ]; then
    for port in "$HTTP_PORT" "$HTTPS_PORT"; do
        if ss -ltn 2> /dev/null | awk '{print $4}' | grep -Eq "[:.]${port}$"; then
            fail "Port $port is already used by another program. Stop it, or set another port in $APP_DIR/.env (HTTP_PORT, HTTPS_PORT)."
        fi
    done
fi

say "Downloading the setup files..."
curl -fsSL "$BASE_URL/docker-compose.yml" -o docker-compose.yml
curl -fsSL "$BASE_URL/Caddyfile" -o Caddyfile

# ---- Start ----
say "Starting the panel (the first time the image is downloaded, this takes a few minutes)..."
docker compose up -d

say "Waiting for the panel to answer..."
address="https://$DOMAIN"
if [ "$HTTPS_PORT" != "443" ]; then
    address="$address:$HTTPS_PORT"
fi

ready=no
for _ in $(seq 1 60); do
    if curl -ksf -o /dev/null --max-time 5 "$address/api/health"; then
        ready=yes
        break
    fi
    sleep 3
done

if [ "$ready" = no ]; then
    warn "The panel did not answer yet. The certificate can take a minute: look at the log with"
    warn "  cd $APP_DIR && docker compose logs web --tail 30"
fi

# ---- The end: a banner and what to do now ----
printf '\033[1;36m'
cat << 'ART'

  ██╗  ██╗ ██╗   ██╗ ██████╗  ██╗ ████████╗
  ██║  ██║ ██║   ██║ ██╔══██╗ ██║ ╚══██╔══╝
  ███████║ ██║   ██║ ██████╔╝ ██║    ██║
  ██╔══██║ ██║   ██║ ██╔══██╗ ██║    ██║
  ██║  ██║ ╚██████╔╝ ██████╔╝ ██║    ██║
  ╚═╝  ╚═╝  ╚═════╝  ╚═════╝  ╚═╝    ╚═╝

  ██████╗   █████╗  ███╗   ██╗ ███████╗ ██╗
  ██╔══██╗ ██╔══██╗ ████╗  ██║ ██╔════╝ ██║
  ██████╔╝ ███████║ ██╔██╗ ██║ █████╗   ██║
  ██╔═══╝  ██╔══██║ ██║╚██╗██║ ██╔══╝   ██║
  ██║      ██║  ██║ ██║ ╚████║ ███████╗ ███████╗
  ╚═╝      ╚═╝  ╚═╝ ╚═╝  ╚═══╝ ╚══════╝ ╚══════╝

ART
printf '\033[0m'

cat << DONE

  The panel is installed. Do these steps in order:

  1. Open the panel in your browser:
       $address

  2. The installer asks for the database. Type exactly this:
       host     : db
       port     : 3306
       name     : panel
       user     : panel
       password : $DB_PASSWORD
     (the password is also saved in $APP_DIR/.env)

  3. In the next page choose the username and password of the admin.

  4. Add the cron job (required: without it nothing runs in the background).
     In the panel open  Management > Settings > General > "Site address and cron",
     copy the wget line and run  crontab -e  on this server to paste it.

  Problems?  cd $APP_DIR && docker compose logs --tail 30

DONE
