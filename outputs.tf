output "resume_deploiement" {
  description = "Résumé complet du déploiement"
  value = {
    projet     = local.projet
    env        = local.env
    version    = var.version_app
    deploy_id  = random_id.deploy_id.hex
    replicas   = local.env_config.replicas
    nb_tables  = length(local.tables)
    nb_sources = length(local.sources)
  }
}

output "fichiers_generes" {
  value = {
    config    = local_file.config_principale.filename
    sql       = local_file.init_sql.filename
    pipelines = [for f in local_file.config_source : f.filename]
    env       = local_file.env_file.filename
    cicd      = local_file.workflow_cicd.filename
    catalogue = local_file.data_catalogue.filename
    manifest  = local_file.manifest_final.filename
  }
}

output "rotation_secrets" {
  description = "Prochaine rotation des secrets"
  value       = time_rotating.rotation_secrets.rotation_rfc3339
}

output "db_password" {
  value     = random_password.db_password.result
  sensitive = true
}
