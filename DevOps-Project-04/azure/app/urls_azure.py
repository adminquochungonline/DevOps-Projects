"""URL configuration for the Azure deployment.

Extends the shared URL config with a probe endpoint used by the Container Apps
startup / readiness / liveness probes, plus a root route so the ingress FQDN
answers on ``/``. Copied into the Django package as
``hello_world_django_app/urls_azure.py`` by ``azure/Dockerfile``.
"""

from django.http import JsonResponse
from django.urls import path
from django.views.decorators.cache import never_cache

from .urls import urlpatterns as base_urlpatterns
from .views import hello_world


@never_cache
def health(request):
    """Liveness/readiness signal.

    Kept intentionally cheap: it proves the WSGI worker can serve a request.
    Add dependency checks (database, cache) here only for readiness, otherwise a
    dependency blip will restart healthy containers.
    """
    return JsonResponse({"status": "ok"})


urlpatterns = [
    path("", hello_world),
    path("health/", health, name="health"),
    *base_urlpatterns,
]
