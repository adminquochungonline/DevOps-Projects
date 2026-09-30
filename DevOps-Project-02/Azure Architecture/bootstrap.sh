#!/usr/bin/env bash
set -Eeuo pipefail

LOG_FILE="/var/log/azure-bootstrap.log"
exec > >(tee -a "$LOG_FILE" | logger -t azure-bootstrap) 2>&1

: "${SITE_REPOSITORY_URL:?SITE_REPOSITORY_URL is required}"
: "${MANAGED_IDENTITY_CLIENT_ID:?MANAGED_IDENTITY_CLIENT_ID is required}"
SITE_REPOSITORY_REF="${SITE_REPOSITORY_REF:-master}"
SITE_SOURCE_PATH="${SITE_SOURCE_PATH:-DevOps-Project-02/html-web-app}"
STORAGE_ACCOUNT_NAME="${STORAGE_ACCOUNT_NAME:-}"
CONFIG_CONTAINER_NAME="${CONFIG_CONTAINER_NAME:-app-config}"

if [[ ! -f /etc/os-release ]]; then
  echo "Unsupported image: /etc/os-release is missing" >&2
  exit 1
fi

# This image bootstrap intentionally targets the Ubuntu image documented in README.md.
. /etc/os-release
if [[ "$ID" != "ubuntu" ]]; then
  echo "Unsupported distribution: $ID. Build the Compute Gallery image from Ubuntu 22.04/24.04." >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y apache2 ca-certificates curl git jq rsync unzip

if ! command -v az >/dev/null 2>&1; then
  echo "Azure CLI is missing. Install and pin it in the Compute Gallery image before publishing." >&2
  exit 1
fi

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

echo "Deploying web content from ${SITE_REPOSITORY_URL}@${SITE_REPOSITORY_REF}"
git clone --depth 1 --branch "$SITE_REPOSITORY_REF" "$SITE_REPOSITORY_URL" "$work_dir/repository"
site_dir="$work_dir/repository/$SITE_SOURCE_PATH"
if [[ ! -f "$site_dir/index.html" ]]; then
  echo "Website entry point not found: $site_dir/index.html" >&2
  exit 1
fi

find /var/www/html -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
rsync -a --delete "$site_dir/" /var/www/html/
printf 'ok\n' >/var/www/html/healthz
chown -R www-data:www-data /var/www/html
find /var/www/html -type d -exec chmod 0755 {} +
find /var/www/html -type f -exec chmod 0644 {} +

# Configuration is optional. Access uses the VMSS user-assigned managed identity;
# no account key, SAS token, or secret is stored on the VM.
if [[ -n "$STORAGE_ACCOUNT_NAME" ]]; then
  mkdir -p /etc/devops-project-02
  identity_ready=false
  for attempt in {1..12}; do
    if az login --identity --client-id "$MANAGED_IDENTITY_CLIENT_ID" --allow-no-subscriptions --output none; then
      identity_ready=true
      break
    fi
    echo "Managed identity is not ready (attempt $attempt/12); retrying..."
    sleep 10
  done

  if [[ "$identity_ready" == "true" ]]; then
    az storage blob download-batch \
      --account-name "$STORAGE_ACCOUNT_NAME" \
      --source "$CONFIG_CONTAINER_NAME" \
      --destination /etc/devops-project-02 \
      --auth-mode login \
      --only-show-errors || echo "No configuration blobs downloaded; continuing with defaults."
  else
    echo "Managed identity login did not become ready; continuing without optional configuration."
  fi
fi

a2enmod headers
cat >/etc/apache2/sites-available/devops-project-02.conf <<'APACHE'
ServerTokens Prod
ServerSignature Off
<VirtualHost *:80>
    ServerName _default_
    DocumentRoot /var/www/html
    ErrorLog syslog:local1
    CustomLog "|/usr/bin/logger -t apache-access" combined

    <Directory /var/www/html>
        Options -Indexes
        AllowOverride None
        Require all granted
    </Directory>

    <Location /healthz>
        ForceType text/plain
        Header set Cache-Control "no-store"
    </Location>
</VirtualHost>
APACHE

a2dissite 000-default
a2ensite devops-project-02
apache2ctl configtest
systemctl enable --now apache2
curl --fail --silent --show-error http://127.0.0.1/healthz

echo "Azure VMSS bootstrap completed successfully. Log: $LOG_FILE"
