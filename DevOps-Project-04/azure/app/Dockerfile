# =============================================================================
# Django image for the Azure Container Apps deployment
# =============================================================================
# Build context is the PROJECT ROOT (DevOps-Project-04), not this folder:
#
#   docker build -f azure/app/Dockerfile -t django-app:dev .
#   az acr build --registry <acr> --image django-app:<tag> --file azure/app/Dockerfile .
#
# Differences from the AWS Dockerfile at the project root (kept separate on
# purpose):
#   * settings module / wsgi path match the real package (hello_world_django_app)
#   * gunicorn + whitenoise are installed from azure/app/requirements.txt
#   * STATIC_ROOT exists, so collectstatic works
#   * /health/ route exists, so the Container Apps probes have a target
# =============================================================================

# ------------------------------------------------------------------------------
# Stage 1: build the virtualenv
# ------------------------------------------------------------------------------
FROM python:3.12-slim AS builder

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
    && rm -rf /var/lib/apt/lists/*

RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

COPY azure/app/requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt

# ------------------------------------------------------------------------------
# Stage 2: runtime
# ------------------------------------------------------------------------------
FROM python:3.12-slim AS production

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PATH="/opt/venv/bin:$PATH" \
    DJANGO_SETTINGS_MODULE=hello_world_django_app.settings_azure \
    PORT=8000

# curl is only needed for local `docker run` health checks; drop it to shrink
# the image further if you rely solely on the Container Apps probes.
RUN apt-get update && apt-get install -y --no-install-recommends \
        curl \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

RUN groupadd --system django && useradd --system --gid django --home-dir /app django

COPY --from=builder /opt/venv /opt/venv

WORKDIR /app

# Explicit copies keep db.sqlite3, __pycache__ and the AWS assets out of the
# image, which also means no .dockerignore is needed for this build.
COPY --chown=django:django manage.py ./
COPY --chown=django:django hello_world_django_app/ ./hello_world_django_app/
COPY --chown=django:django azure/app/settings_azure.py azure/app/urls_azure.py ./hello_world_django_app/

RUN mkdir -p /app/staticfiles && chown -R django:django /app

USER django

# SECRET_KEY is required at runtime; collectstatic only needs *a* value, so a
# throwaway build-time key is used here and never ends up in the image config.
RUN DJANGO_SECRET_KEY="build-time-only-not-used-at-runtime" \
    python manage.py collectstatic --noinput --clear

EXPOSE 8000

# Mirrors the Container Apps startup/readiness/liveness probes.
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD curl -fsS "http://localhost:${PORT}/health/" || exit 1

# 2 workers + 4 threads fits the 0.5 vCPU / 1 GiB replica sized in the IaC.
# Scale out with replicas (KEDA), not with workers inside one container.
CMD ["sh", "-c", "exec gunicorn hello_world_django_app.wsgi:application \
    --bind 0.0.0.0:${PORT} \
    --workers 2 \
    --threads 4 \
    --timeout 60 \
    --graceful-timeout 30 \
    --access-logfile - \
    --error-logfile - \
    --forwarded-allow-ips '*'"]
