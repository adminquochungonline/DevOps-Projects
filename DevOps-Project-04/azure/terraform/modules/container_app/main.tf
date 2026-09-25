# Container Apps module - Azure equivalent of the AWS bundle
# "ECS task definition + ECS service + ALB + target group + application autoscaling".
# Container Apps folds all of that into one resource: the template is the task
# definition, revisions are deployments, the built-in Envoy ingress is the load
# balancer, and the scale rules are KEDA-driven autoscaling.

locals {
  image_tag = try(element(split(":", var.container_image), 1), "latest")

  # One revision per image tag, so `az containerapp revision list` reads like a
  # deployment history instead of a list of hashes.
  revision_suffix = var.revision_suffix != "" ? var.revision_suffix : lower(replace(local.image_tag, "/[^a-zA-Z0-9-]/", "-"))
}

resource "azurerm_container_app" "main" {
  name                         = var.name_prefix
  resource_group_name          = var.resource_group_name
  container_app_environment_id = var.container_app_environment_id
  revision_mode                = "Single"
  tags                         = var.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [var.managed_identity_id]
  }

  # Registry pull via managed identity: no credentials stored on the app.
  registry {
    server   = var.registry_login_server
    identity = var.managed_identity_id
  }

  secret {
    name  = "django-secret-key"
    value = var.django_secret_key
  }

  ingress {
    # NOTE: external_enabled = true publishes a public FQDN with no
    # authentication in front of it. For anything beyond a demo, enable
    # Container Apps auth (Entra ID) or front it with Front Door / App Gateway + WAF.
    external_enabled           = var.external_ingress
    target_port                = var.target_port
    transport                  = "auto"
    allow_insecure_connections = false

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  template {
    min_replicas    = var.min_replicas
    max_replicas    = var.max_replicas
    revision_suffix = local.revision_suffix

    http_scale_rule {
      name                = "http-concurrency"
      concurrent_requests = tostring(var.concurrent_requests)
    }

    container {
      name   = "django"
      image  = var.container_image
      cpu    = var.cpu
      memory = var.memory

      env {
        name  = "DJANGO_SETTINGS_MODULE"
        value = "hello_world_django_app.settings_azure"
      }

      env {
        name  = "DJANGO_ALLOWED_HOSTS"
        value = var.allowed_hosts
      }

      env {
        name  = "DJANGO_CSRF_TRUSTED_ORIGINS"
        value = var.csrf_trusted_origins
      }

      env {
        name  = "PORT"
        value = tostring(var.target_port)
      }

      env {
        name        = "DJANGO_SECRET_KEY"
        secret_name = "django-secret-key"
      }

      # Startup: gives gunicorn time to boot before failures count.
      startup_probe {
        transport               = "HTTP"
        port                    = var.target_port
        path                    = "/health/"
        interval_seconds        = 5
        timeout                 = 3
        failure_count_threshold = 12
      }

      # Readiness: gates traffic during rolling revision switches.
      readiness_probe {
        transport               = "HTTP"
        port                    = var.target_port
        path                    = "/health/"
        interval_seconds        = 10
        timeout                 = 3
        failure_count_threshold = 3
      }

      # Liveness: restarts a wedged replica.
      liveness_probe {
        transport               = "HTTP"
        port                    = var.target_port
        path                    = "/health/"
        initial_delay           = 10
        interval_seconds        = 30
        timeout                 = 5
        failure_count_threshold = 3
      }
    }
  }

  lifecycle {
    precondition {
      condition     = var.django_secret_key != ""
      error_message = "django_secret_key is required when deploying the app. Pass TF_VAR_django_secret_key (Jenkins credential 'django-secret-key')."
    }

    precondition {
      condition     = !endswith(var.container_image, ":latest")
      error_message = "Use an immutable tag (build number, git sha or timestamp) instead of ':latest' so revisions stay traceable and rollbacks are possible."
    }
  }
}
