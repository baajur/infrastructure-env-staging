#####################################################################
# variables for staging environment
#####################################################################
variable "athene2_database_password_default" {
  description = "Password for default username in athene2 database."
}

variable "athene2_database_password_readonly" {
  description = "Password for 'readonly user' in athene2 database."
}

variable "kpi_grafana_admin_password" {
  description = "Admin password for grafana."
}

variable "kpi_kpi_database_password_postgres" {
  description = "Password for postgres postgres user."
}

variable "kpi_kpi_database_password_default" {
  description = "Password for default postgres user."
}

variable "kpi_kpi_database_password_readonly" {
  description = "Password for readonly postgres user."
}

variable "cloudflare_token" {
  description = "API Token for cloudflare account."
}

variable "athene2_php_smtp_password" {
  description = "Password for smtp"
}

variable "athene2_php_tracking_switch" {
  description = "Flag whether to activate tracking or not -> usually only set to true in production"
  default     = "false"
}

variable "athene2_php_recaptcha_key" {
  description = "Key for recaptcha"
}

variable "athene2_php_recaptcha_secret" {
  description = "Secret for recaptcha"
}

variable "athene2_php_newsletter_key" {
  description = "Key for newsletter"
}

variable "kpi_grafana_serlo_password" {
  description = "Password for grafana serlo user"
}

variable "api_active_donors_google_api_key" {
  type = string
}

variable "api_active_donors_google_spreadsheet_id" {
  type = string
}

variable "api_swr_queue_dashboard_username" {
  type = string
}

variable "api_swr_queue_dashboard_password" {
  type = string
}
