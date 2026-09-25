#!/usr/bin/env bash
# =============================================================================
# One-shot deployment of the Django app to Azure Container Apps (Bicep track).
# =============================================================================
# Order matters: the registry must exist before an image can be pushed, and the
# image must exist before the container app can pull it.
#
#   1. platform.bicep  -> ACR + Log Analytics + Container Apps env + identity
#   2. az acr build    -> build the image in ACR (no local Docker needed)
#   3. app.bicep       -> container app revision pointing at that image
#
# Usage (from anywhere):
#   RESOURCE_GROUP=devops04-django-rg LOCATION=southeastasia ./deploy.sh
#
# Environment variables:
#   RESOURCE_GROUP     target resource group                 (default devops04-django-rg, separate from the Terraform track)
#   LOCATION           Azure region                          (default southeastasia)
#   PREFIX             resource name prefix                  (default devops04)
#   IMAGE_NAME         repository name inside ACR            (default django-app)
#   IMAGE_TAG          image tag                             (default current UTC timestamp)
#   DJANGO_SECRET_KEY  Django SECRET_KEY                     (generated if unset)
#   ALLOWED_HOSTS      Django ALLOWED_HOSTS                  (default *, narrowed after first deploy)
# =============================================================================

set -euo pipefail

RESOURCE_GROUP="${RESOURCE_GROUP:-devops04-django-rg}"
LOCATION="${LOCATION:-southeastasia}"
PREFIX="${PREFIX:-devops04}"
IMAGE_NAME="${IMAGE_NAME:-django-app}"
IMAGE_TAG="${IMAGE_TAG:-$(date -u +%Y%m%d%H%M%S)}"
ALLOWED_HOSTS="${ALLOWED_HOSTS:-*}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Docker build context: the project root (two levels up from azure/bicep).
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

command -v az >/dev/null || { echo "az CLI is required" >&2; exit 1; }

if [[ -z "${DJANGO_SECRET_KEY:-}" ]]; then
  echo ">> DJANGO_SECRET_KEY not set, generating an ephemeral one."
  echo "   Store it in Key Vault (or a pipeline secret) and pass it in for repeat deploys,"
  echo "   otherwise every run invalidates existing sessions."
  DJANGO_SECRET_KEY="$(LC_ALL=C tr -dc 'A-Za-z0-9!@#%^&*()-_=+' </dev/urandom | head -c 64)"
fi

# Secure parameters go through a 0600 temp file instead of the command line,
# which would expose them in the process list and in shell history.
umask 077
SECRET_PARAMS_FILE="$(mktemp -t dp04-secret-XXXXXX.json)"
cleanup() { rm -f "${SECRET_PARAMS_FILE}"; }
trap cleanup EXIT

echo "==> [0/3] Resource group ${RESOURCE_GROUP} (${LOCATION})"
az group create --name "${RESOURCE_GROUP}" --location "${LOCATION}" --output none

echo "==> [1/3] Platform layer (registry, logs, environment, identity)"
PLATFORM_OUTPUTS="$(az deployment group create \
  --resource-group "${RESOURCE_GROUP}" \
  --name "dp04-platform-${IMAGE_TAG}" \
  --template-file "${SCRIPT_DIR}/platform.bicep" \
  --parameters prefix="${PREFIX}" location="${LOCATION}" \
  --query properties.outputs \
  --output json)"

REGISTRY_NAME="$(echo "${PLATFORM_OUTPUTS}" | python3 -c 'import json,sys;print(json.load(sys.stdin)["registryName"]["value"])')"
REGISTRY_LOGIN_SERVER="$(echo "${PLATFORM_OUTPUTS}" | python3 -c 'import json,sys;print(json.load(sys.stdin)["registryLoginServer"]["value"])')"
ENVIRONMENT_ID="$(echo "${PLATFORM_OUTPUTS}" | python3 -c 'import json,sys;print(json.load(sys.stdin)["environmentId"]["value"])')"
IDENTITY_ID="$(echo "${PLATFORM_OUTPUTS}" | python3 -c 'import json,sys;print(json.load(sys.stdin)["identityId"]["value"])')"

echo "    registry:    ${REGISTRY_LOGIN_SERVER}"
echo "    environment: ${ENVIRONMENT_ID##*/}"

echo "==> [2/3] Building ${IMAGE_NAME}:${IMAGE_TAG} in ACR"
az acr build \
  --registry "${REGISTRY_NAME}" \
  --image "${IMAGE_NAME}:${IMAGE_TAG}" \
  --file azure/app/Dockerfile \
  "${PROJECT_ROOT}"

echo "==> [3/3] Container app revision"
cat > "${SECRET_PARAMS_FILE}" <<JSON
{
  "\$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "djangoSecretKey": { "value": "${DJANGO_SECRET_KEY}" }
  }
}
JSON

APP_URL="$(az deployment group create \
  --resource-group "${RESOURCE_GROUP}" \
  --name "dp04-app-${IMAGE_TAG}" \
  --template-file "${SCRIPT_DIR}/app.bicep" \
  --parameters "@${SECRET_PARAMS_FILE}" \
  --parameters prefix="${PREFIX}" location="${LOCATION}" \
               environmentId="${ENVIRONMENT_ID}" \
               managedIdentityId="${IDENTITY_ID}" \
               registryLoginServer="${REGISTRY_LOGIN_SERVER}" \
               containerImage="${REGISTRY_LOGIN_SERVER}/${IMAGE_NAME}:${IMAGE_TAG}" \
               allowedHosts="${ALLOWED_HOSTS}" \
  --query properties.outputs.appUrl.value \
  --output tsv)"

echo
echo "Deployed: ${APP_URL}"
echo "Probe:    ${APP_URL}/health/"
echo
echo "Reminder: ingress is public and unauthenticated. Restrict ALLOWED_HOSTS to"
echo "the FQDN above and add Entra ID auth or Front Door + WAF before real use."

echo "==> Smoke test"
for attempt in $(seq 1 10); do
  code="$(curl -s -o /dev/null -w '%{http_code}' "${APP_URL}/health/" || echo 000)"
  echo "    attempt ${attempt}: HTTP ${code}"
  if [[ "${code}" == "200" ]]; then
    echo "    healthy"
    exit 0
  fi
  sleep 10
done

echo "    health endpoint did not return 200 in time; check:" >&2
echo "    az containerapp logs show -g ${RESOURCE_GROUP} -n ${PREFIX}-django-app --tail 100" >&2
exit 1
