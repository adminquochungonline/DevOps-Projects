"""Production settings for the Azure Container Apps deployment.

This module layers on top of the shared development settings in
``hello_world_django_app/settings.py`` so the AWS variant of this project stays
untouched. ``azure/Dockerfile`` copies it into the Django package as
``hello_world_django_app/settings_azure.py`` and points
``DJANGO_SETTINGS_MODULE`` at it.

Every environment-specific value comes from environment variables, which
Container Apps sources from plain env vars or from secrets / Key Vault
references.
"""

import os

from django.core.exceptions import ImproperlyConfigured

from .settings import *  # noqa: F401,F403
from .settings import BASE_DIR, MIDDLEWARE


def env(name, default=None, required=False):
    """Read an environment variable, optionally failing fast when missing."""
    value = os.environ.get(name, default)
    if required and not value:
        raise ImproperlyConfigured(
            f"Environment variable {name} is required by settings_azure"
        )
    return value


def env_list(name, default=""):
    return [item.strip() for item in env(name, default).split(",") if item.strip()]


def env_bool(name, default="false"):
    return env(name, default).strip().lower() in {"1", "true", "yes", "on"}


# ---------------------------------------------------------------------------
# Core
# ---------------------------------------------------------------------------

# Injected as a Container Apps secret; there is deliberately no fallback to the
# development key committed in settings.py.
SECRET_KEY = env("DJANGO_SECRET_KEY", required=True)

DEBUG = env_bool("DJANGO_DEBUG", "false")

# Defaults to "*" so a first deploy works before the ingress FQDN is known.
# Narrow it to the FQDN (and any custom domain) as soon as it is.
ALLOWED_HOSTS = env_list("DJANGO_ALLOWED_HOSTS", "*")

# Needed for POST/form views once a custom domain is attached.
CSRF_TRUSTED_ORIGINS = env_list("DJANGO_CSRF_TRUSTED_ORIGINS")

# Adds /health/ (probe target) on top of the shared URL config.
ROOT_URLCONF = "hello_world_django_app.urls_azure"

# ---------------------------------------------------------------------------
# Static files - served by WhiteNoise from inside the container
# ---------------------------------------------------------------------------

STATIC_ROOT = BASE_DIR / "staticfiles"

MIDDLEWARE = [
    "django.middleware.security.SecurityMiddleware",
    "whitenoise.middleware.WhiteNoiseMiddleware",
    *[m for m in MIDDLEWARE if m != "django.middleware.security.SecurityMiddleware"],
]

STORAGES = {
    "default": {
        "BACKEND": "django.core.files.storage.FileSystemStorage",
    },
    "staticfiles": {
        "BACKEND": "whitenoise.storage.CompressedManifestStaticFilesStorage",
    },
}

# ---------------------------------------------------------------------------
# TLS / proxy
# ---------------------------------------------------------------------------
# Container Apps terminates TLS at the Envoy ingress and forwards plain HTTP to
# the container, so Django learns the original scheme from the forwarded header.

SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")
USE_X_FORWARDED_HOST = True

SECURE_SSL_REDIRECT = env_bool("DJANGO_SECURE_SSL_REDIRECT", "true")
# Probes hit the container directly over HTTP; redirecting them would mask real
# failures behind 301s.
SECURE_REDIRECT_EXEMPT = [r"^health/$"]

SECURE_HSTS_SECONDS = int(env("DJANGO_SECURE_HSTS_SECONDS", "31536000"))
SECURE_HSTS_INCLUDE_SUBDOMAINS = True
SECURE_HSTS_PRELOAD = True
SECURE_CONTENT_TYPE_NOSNIFF = True
X_FRAME_OPTIONS = "DENY"
SESSION_COOKIE_SECURE = True
CSRF_COOKIE_SECURE = True

# ---------------------------------------------------------------------------
# Database
# ---------------------------------------------------------------------------
# The bundled SQLite file lives in the container filesystem, which is ephemeral:
# every revision and every replica starts from the image copy. That is fine for
# this hello-world app. For real workloads switch DATABASES to Azure Database
# for PostgreSQL Flexible Server (see azure/README.md, "Next steps").

# ---------------------------------------------------------------------------
# Logging - stdout/stderr is collected by Container Apps into Log Analytics
# ---------------------------------------------------------------------------

LOGGING = {
    "version": 1,
    "disable_existing_loggers": False,
    "formatters": {
        "verbose": {
            "format": "{levelname} {asctime} {name} {message}",
            "style": "{",
        },
    },
    "handlers": {
        "console": {
            "class": "logging.StreamHandler",
            "formatter": "verbose",
        },
    },
    "root": {
        "handlers": ["console"],
        "level": env("DJANGO_LOG_LEVEL", "INFO"),
    },
    "loggers": {
        "django.request": {
            "handlers": ["console"],
            "level": "WARNING",
            "propagate": False,
        },
    },
}
