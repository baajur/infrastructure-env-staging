#####################################################################
# settings for staging
#####################################################################
locals {
  domain  = "serlo-staging.dev"
  project = "serlo-staging"

  credentials_path = "secrets/serlo-staging-terraform-15240e38ec22.json"
  service_account  = "terraform@serlo-staging.iam.gserviceaccount.com"
  region           = "europe-west3"

  cluster_machine_type = "n1-standard-2"

  serlo_org_image_tags = {
    server = {
      httpd             = "5.0.0"
      php               = "5.0.0"
      notifications_job = "2.0.1"
    }
    editor_renderer        = "3.0.0"
    legacy_editor_renderer = "2.0.0"
    frontend               = "1.0.0"
  }
  varnish_image = "eu.gcr.io/serlo-shared/varnish:6.0"

  athene2_php_definitions-file_path = "secrets/athene2/definitions.staging.php"

  athene2_database_instance_name = "${local.project}-mysql-instance-10072019-1"
  kpi_database_instance_name     = "${local.project}-postgres-instance-10072019-2"
}

#####################################################################
# providers
#####################################################################
provider "cloudflare" {
  version = "~> 2.0"
  email   = var.cloudflare_email
  api_key = var.cloudflare_token
}

provider "google" {
  version     = "~> 2.18"
  project     = local.project
  credentials = file("${local.credentials_path}")
}

provider "google-beta" {
  version     = "~> 2.18"
  project     = local.project
  credentials = file("${local.credentials_path}")
}

provider "helm" {
  version = "~> 0.10"
  kubernetes {
    host     = module.gcloud.host
    username = ""
    password = ""

    client_certificate     = base64decode(module.gcloud.client_certificate)
    client_key             = base64decode(module.gcloud.client_key)
    cluster_ca_certificate = base64decode(module.gcloud.cluster_ca_certificate)
  }
}

provider "kubernetes" {
  version          = "~> 1.8"
  host             = module.gcloud.host
  load_config_file = false

  client_certificate     = base64decode(module.gcloud.client_certificate)
  client_key             = base64decode(module.gcloud.client_key)
  cluster_ca_certificate = base64decode(module.gcloud.cluster_ca_certificate)
}

provider "null" {
  version = "~> 2.1"
}

provider "random" {
  version = "~> 2.2"
}

provider "template" {
  version = "~> 2.1"
}

provider "tls" {
  version = "~> 2.1"
}

#####################################################################
# modules
#####################################################################
module "gcloud" {
  source                   = "github.com/serlo/infrastructure-modules-gcloud.git//gcloud?ref=193c415dc00b0a40e1790ad224864d3df6cfba3e"
  project                  = local.project
  clustername              = "${local.project}-cluster"
  location                 = "europe-west3-a"
  region                   = local.region
  machine_type             = local.cluster_machine_type
  issue_client_certificate = true
  logging_service          = "logging.googleapis.com/kubernetes"
  monitoring_service       = "monitoring.googleapis.com/kubernetes"

  providers = {
    google      = google
    google-beta = google-beta
    kubernetes  = kubernetes
  }
}

module "gcloud_mysql" {
  source                     = "github.com/serlo/infrastructure-modules-gcloud.git//gcloud_mysql?ref=193c415dc00b0a40e1790ad224864d3df6cfba3e"
  database_instance_name     = local.athene2_database_instance_name
  database_connection_name   = "${local.project}:${local.region}:${local.athene2_database_instance_name}"
  database_region            = local.region
  database_name              = "serlo"
  database_tier              = "db-f1-micro"
  database_private_network   = module.gcloud.network
  private_ip_address_range   = module.gcloud.private_ip_address_range
  database_password_default  = var.athene2_database_password_default
  database_password_readonly = var.athene2_database_password_readonly

  providers = {
    google      = google
    google-beta = google-beta
  }
}

module "gcloud_postgres" {
  source                   = "github.com/serlo/infrastructure-modules-gcloud.git//gcloud_postgres?ref=193c415dc00b0a40e1790ad224864d3df6cfba3e"
  database_instance_name   = local.kpi_database_instance_name
  database_connection_name = "${local.project}:${local.region}:${local.kpi_database_instance_name}"
  database_region          = local.region
  database_names           = ["kpi", "hydra"]
  database_private_network = module.gcloud.network
  private_ip_address_range = module.gcloud.private_ip_address_range

  database_password_postgres = var.kpi_kpi_database_password_postgres
  database_username_default  = module.kpi.kpi_database_username_default
  database_password_default  = var.kpi_kpi_database_password_default
  database_username_readonly = module.kpi.kpi_database_username_readonly
  database_password_readonly = var.kpi_kpi_database_password_readonly

  providers = {
    google      = google
    google-beta = google-beta
  }
}

module "serlo_org" {
  source = "github.com/serlo/infrastructure-modules-serlo.org.git//?ref=972a0aab32801973cfc0f8d44f7676d16f7f9d08"

  namespace         = kubernetes_namespace.serlo_org_namespace.metadata.0.name
  image_pull_policy = "IfNotPresent"

  server = {
    app_replicas = 1
    image_tags   = local.serlo_org_image_tags.server

    domain                = local.domain
    definitions_file_path = local.athene2_php_definitions-file_path

    resources = {
      httpd = {
        limits = {
          cpu    = "200m"
          memory = "200Mi"
        }
        requests = {
          cpu    = "100m"
          memory = "100Mi"
        }
      }
      php = {
        limits = {
          cpu    = "700m"
          memory = "600Mi"
        }
        requests = {
          cpu    = "400m"
          memory = "200Mi"
        }
      }
    }

    recaptcha = {
      key    = var.athene2_php_recaptcha_key
      secret = var.athene2_php_recaptcha_secret
    }

    smtp_password = var.athene2_php_smtp_password
    mailchimp_key = var.athene2_php_newsletter_key

    enable_tracking   = var.athene2_php_tracking_switch
    enable_basic_auth = true
    enable_cronjobs   = true
    enable_mail_mock  = true

    database = {
      host     = module.gcloud_mysql.database_private_ip_address
      username = "serlo"
      password = var.athene2_database_password_default
    }

    database_readonly = {
      username = "serlo_readonly"
      password = var.athene2_database_password_readonly
    }

    upload_secret   = file("secrets/serlo-org-6bab84a1b1a5.json")
    hydra_admin_uri = module.hydra.admin_uri
    feature_flags   = "['donation-banner' => true]"
    redis_hosts     = "[]"
  }

  editor_renderer = {
    app_replicas = 1
    image_tag    = local.serlo_org_image_tags.editor_renderer
  }

  legacy_editor_renderer = {
    app_replicas = 1
    image_tag    = local.serlo_org_image_tags.legacy_editor_renderer
  }

  frontend = {
    app_replicas = 1
    image_tag    = local.serlo_org_image_tags.frontend
  }

  varnish = {
    app_replicas = 1
    image        = local.varnish_image
    memory       = "100M"
  }

  providers = {
    kubernetes = kubernetes
    random     = random
    template   = template
  }
}

module "athene2_dbsetup" {
  source                    = "github.com/serlo/infrastructure-modules-serlo.org.git//athene2_dbsetup?ref=972a0aab32801973cfc0f8d44f7676d16f7f9d08"
  namespace                 = kubernetes_namespace.serlo_org_namespace.metadata.0.name
  database_password_default = var.athene2_database_password_default
  database_host             = module.gcloud_mysql.database_private_ip_address
  # currently disable dbsetup via shared bucket in staging.
  # gcloud_service_account_key  = module.gcloud_dbdump_reader.account_key
  # gcloud_service_account_name = module.gcloud_dbdump_reader.account_name
  gcloud_service_account_key  = ""
  gcloud_service_account_name = ""

  providers = {
    kubernetes = kubernetes
    null       = null
  }
}

module "kpi" {
  source = "github.com/serlo/infrastructure-modules-kpi.git//kpi?ref=v1.3.0"
  domain = local.domain

  grafana_admin_password = var.kpi_grafana_admin_password
  grafana_serlo_password = var.kpi_grafana_serlo_password

  athene2_database_host              = module.gcloud_mysql.database_private_ip_address
  athene2_database_password_readonly = var.athene2_database_password_readonly

  kpi_database_host              = module.gcloud_postgres.database_private_ip_address
  kpi_database_password_default  = var.kpi_kpi_database_password_default
  kpi_database_password_readonly = var.kpi_kpi_database_password_readonly

  grafana_image        = "eu.gcr.io/serlo-shared/kpi-grafana:1.0.1"
  mysql_importer_image = "eu.gcr.io/serlo-shared/kpi-mysql-importer:1.2.1"
  aggregator_image     = "eu.gcr.io/serlo-shared/kpi-aggregator:1.3.2"
}

module "ingress-nginx" {
  source      = "github.com/serlo/infrastructure-modules-shared.git//ingress-nginx?ref=86fa9688de6dbde14799c484ca5de655df51c12d"
  namespace   = kubernetes_namespace.ingress_nginx_namespace.metadata.0.name
  ip          = module.gcloud.staticip_regional_address
  domain      = "*.${local.domain}"
  nginx_image = "quay.io/kubernetes-ingress-controller/nginx-ingress-controller:0.24.1"

  providers = {
    kubernetes = kubernetes
    tls        = tls
  }
}

module "cloudflare" {
  source  = "github.com/serlo/infrastructure-modules-env-shared.git//cloudflare?ref=5175dfff7cc6a52d85cc66ae8c690c67f5539200"
  domain  = local.domain
  ip      = module.gcloud.staticip_regional_address
  zone_id = "ffbc61a7597fd0177bbeb8fff6fa31c8"

  providers = {
    cloudflare = cloudflare
  }
}

module "hydra" {
  source      = "github.com/serlo/infrastructure-modules-shared.git//hydra?ref=86fa9688de6dbde14799c484ca5de655df51c12d"
  dsn         = "postgres://${module.kpi.kpi_database_username_default}:${var.kpi_kpi_database_password_default}@${module.gcloud_postgres.database_private_ip_address}/hydra"
  url_login   = "https://de.${local.domain}/auth/hydra/login"
  url_consent = "https://de.${local.domain}/auth/hydra/consent"
  host        = "hydra.${local.domain}"
  namespace   = kubernetes_namespace.hydra_namespace.metadata.0.name

  providers = {
    helm       = helm
    kubernetes = kubernetes
    random     = random
    template   = template
    tls        = tls
  }
}

module "rocket-chat" {
  source = "github.com/serlo/infrastructure-modules-shared.git//rocket-chat?ref=86fa9688de6dbde14799c484ca5de655df51c12d"

  host      = "community.${local.domain}"
  namespace = kubernetes_namespace.community_namespace.metadata.0.name
  image_tag = "2.2.1"

  mongodump = {
    image         = "eu.gcr.io/serlo-shared/mongodb-tools-base:1.0.1"
    schedule      = "0 0 * * *"
    bucket_prefix = local.project
  }

  smtp_password = var.athene2_php_smtp_password

  providers = {
    google     = google
    helm       = helm
    kubernetes = kubernetes
    random     = random
    template   = template
  }
}

#####################################################################
# ingress
#####################################################################
resource "kubernetes_ingress" "kpi_ingress" {
  metadata {
    name      = "kpi-ingress"
    namespace = kubernetes_namespace.kpi_namespace.metadata.0.name

    annotations = {
      "kubernetes.io/ingress.class" = "nginx"
    }
  }

  spec {
    rule {
      host = "stats.${local.domain}"

      http {
        path {
          path = "/"

          backend {
            service_name = module.kpi.grafana_service_name
            service_port = module.kpi.grafana_service_port
          }
        }
      }
    }
  }
}

resource "kubernetes_ingress" "athene2_ingress" {
  metadata {
    name      = "athene2-ingress"
    namespace = kubernetes_namespace.serlo_org_namespace.metadata.0.name

    annotations = {
      "kubernetes.io/ingress.class"             = "nginx",
      "nginx.ingress.kubernetes.io/auth-type"   = "basic",
      "nginx.ingress.kubernetes.io/auth-secret" = "basic-auth-ingress-secret",
      "nginx.ingress.kubernetes.io/auth-realm"  = "Authentication Required"
    }
  }

  spec {
    backend {
      service_name = module.serlo_org.service_name
      service_port = module.serlo_org.service_port
    }
  }
}

resource "kubernetes_secret" "basic_auth_ingress_secret" {

  metadata {
    name      = "basic-auth-ingress-secret"
    namespace = kubernetes_namespace.serlo_org_namespace.metadata.0.name
  }

  data = {
    auth = "serloteam:$apr1$L6BuktMk$qfh8xvsWsPi3uXB0fIiu1/"
  }
}

#####################################################################
# namespaces
#####################################################################
resource "kubernetes_namespace" "serlo_org_namespace" {
  metadata {
    name = "serlo-org"
  }
}

resource "kubernetes_namespace" "kpi_namespace" {
  metadata {
    name = "kpi"
  }
}

resource "kubernetes_namespace" "community_namespace" {
  metadata {
    name = "community"
  }
}

resource "kubernetes_namespace" "hydra_namespace" {
  metadata {
    name = "hydra"
  }
}

resource "kubernetes_namespace" "ingress_nginx_namespace" {
  metadata {
    name = "ingress-nginx"
  }
}
