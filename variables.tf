variable "nom_projet" {
  description = "Nom du projet data"
  type        = string
  default     = "etl_portfolio"
  validation {
    condition     = can(regex("^[a-z][a-z0-9_]*$", var.nom_projet))
    error_message = "Minuscules, chiffres et underscores uniquement."
  }
}
variable "environnement" {
  description = "Environnement cible"
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environnement)
    error_message = "Valeurs : dev, staging, prod."
  }
}
variable "version_app" {
  description = "Version de l'application (semver)"
  type        = string
  default     = "1.0.0"
  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.version_app))
    error_message = "Format semver : X.Y.Z"
  }
}
variable "alertes_email" {
  description = "Email pour les alertes"
  type        = string
  default     = "equipe-data@company.com"
}
