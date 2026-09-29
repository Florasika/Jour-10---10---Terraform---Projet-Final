# ============================================================
#  JOUR 10 / 10 — Terraform : Projet Final
#  Infrastructure data complète — combines J1 → J9
# ============================================================

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    local  = { source = "hashicorp/local",  version = "~> 2.4" }
    random = { source = "hashicorp/random", version = "~> 3.6" }
    null   = { source = "hashicorp/null",   version = "~> 3.2" }
    time   = { source = "hashicorp/time",   version = "~> 0.11" }
  }
  backend "local" {}
}

provider "local"  {}
provider "random" {}
provider "null"   {}
provider "time"   {}

# ════════════════════════════════════════════════════════════
#  LOCALS — Configuration centralisée (J1, J4, J8)
# ════════════════════════════════════════════════════════════
locals {
  projet = var.nom_projet
  env    = terraform.workspace == "default" ? var.environnement : terraform.workspace
  ts     = formatdate("YYYYMMDD-HHmm", timestamp())

  # Config par environnement (J3 — workspaces)
  env_config = lookup({
    dev     = { replicas = 1, log_level = "DEBUG",   batch = 100,  retries = 2 }
    staging = { replicas = 2, log_level = "INFO",    batch = 500,  retries = 3 }
    prod    = { replicas = 3, log_level = "WARNING", batch = 1000, retries = 5 }
  }, local.env, { replicas = 1, log_level = "DEBUG", batch = 100, retries = 2 })

  # Schéma BDD complet (J8)
  tables = {
    ventes_raw   = { desc = "Données brutes", index = ["date", "vendeur"] }
    ventes_clean = { desc = "Données enrichies", index = ["date", "categorie"] }
    kpis         = { desc = "KPIs journaliers", index = [] }
    pipeline_runs= { desc = "Historique des runs", index = ["date", "statut"] }
  }

  # Sources de données (J8)
  sources = {
    api    = { type = "http",       schedule = "0 6 * * *" }
    sftp   = { type = "sftp",       schedule = "0 7 * * *" }
    db_erp = { type = "postgresql", schedule = "0 5 * * *" }
  }

  # Modules de pipeline (J2)
  modules_pipeline = ["extract", "transform", "load", "validate", "notify"]
}

# ════════════════════════════════════════════════════════════
#  RANDOM — IDs et secrets (J4)
# ════════════════════════════════════════════════════════════
resource "random_id" "deploy_id" {
  byte_length = 4
  keepers = {
    version = var.version_app
    env     = local.env
  }
}

resource "random_password" "db_password" {
  length  = 20
  special = false
}

# ════════════════════════════════════════════════════════════
#  TIME — Rotation et pauses (J9)
# ════════════════════════════════════════════════════════════
resource "time_rotating" "rotation_secrets" {
  rotation_days = 30
}

# ════════════════════════════════════════════════════════════
#  MODULE CONFIG — Fichiers de configuration (J2, J4)
# ════════════════════════════════════════════════════════════
resource "local_file" "config_principale" {
  filename        = "${path.module}/output/${local.env}/config.json"
  file_permission = "0644"

  content = jsonencode({
    meta = {
      projet     = local.projet
      env        = local.env
      version    = var.version_app
      deploy_id  = random_id.deploy_id.hex
      deploye_le = local.ts
    }
    infrastructure = {
      replicas   = local.env_config.replicas
      log_level  = local.env_config.log_level
      batch_size = local.env_config.batch
      max_retries= local.env_config.retries
    }
    base_de_donnees = {
      nom          = "${local.projet}_${local.env}"
      nb_tables    = length(local.tables)
      rotation     = time_rotating.rotation_secrets.rotation_rfc3339
    }
    pipeline = {
      sources  = keys(local.sources)
      modules  = local.modules_pipeline
      schedule = "0 6 * * *"
    }
  })

  lifecycle {
    create_before_destroy = true  # J9
  }
}

# ════════════════════════════════════════════════════════════
#  MODULE SQL — Scripts base de données (J8)
# ════════════════════════════════════════════════════════════
resource "local_file" "init_sql" {
  filename        = "${path.module}/output/${local.env}/sql/init.sql"
  file_permission = "0644"

  content = join("\n\n", concat(
    ["-- Généré par Terraform — ${local.projet} [${local.env}]",
     "-- Deploy ID : ${random_id.deploy_id.hex}",
     "CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\";"],
    [for nom, t in local.tables :
      "-- ${t.desc}\nCREATE TABLE IF NOT EXISTS ${nom} (\n    id SERIAL PRIMARY KEY,\n    date DATE,\n    charge_le TIMESTAMP DEFAULT NOW()\n);\n${join("\n", [for i in t.index : "CREATE INDEX IF NOT EXISTS idx_${nom}_${i} ON ${nom}(${i});"])}"],
    ["-- Vues\nCREATE OR REPLACE VIEW v_resume AS SELECT COUNT(*) AS nb_ventes FROM ventes_clean;"]
  ))
}

# ════════════════════════════════════════════════════════════
#  MODULE PIPELINES — Configs sources (J4, J8)
# ════════════════════════════════════════════════════════════
resource "local_file" "config_source" {
  for_each        = local.sources  # J4 — for_each
  filename        = "${path.module}/output/${local.env}/pipelines/${each.key}.json"
  file_permission = "0644"

  content = jsonencode({
    pipeline_id  = "${local.projet}-${each.key}-${local.env}-${random_id.deploy_id.hex}"
    source       = { type = each.value.type, schedule = each.value.schedule }
    destination  = { db = "${local.projet}_${local.env}", table = "ventes_raw" }
    parametres   = {
      batch_size  = local.env_config.batch
      max_retries = local.env_config.retries
      idempotent  = true
    }
    alertes = { email = var.alertes_email, seuil_erreur = 0.05 }
  })
}

# ════════════════════════════════════════════════════════════
#  MODULE ENV — Variables d'environnement (J1)
# ════════════════════════════════════════════════════════════
resource "local_file" "env_file" {
  filename        = "${path.module}/output/${local.env}/.env"
  file_permission = "0600"  # J4 — sécurité

  content = <<-EOT
    # Généré par Terraform — ${local.projet} [${local.env}]
    PROJET=${local.projet}
    ENV=${local.env}
    VERSION=${var.version_app}
    DEPLOY_ID=${random_id.deploy_id.hex}
    DB_NAME=${local.projet}_${local.env}
    DB_PASSWORD=${random_password.db_password.result}
    LOG_LEVEL=${local.env_config.log_level}
    BATCH_SIZE=${local.env_config.batch}
    ALERTES_EMAIL=${var.alertes_email}
  EOT

  lifecycle {
    ignore_changes = [content]  # J9 — modifiable par ops
  }
}

# ════════════════════════════════════════════════════════════
#  MODULE CI/CD — Workflows GitHub Actions (J5)
# ════════════════════════════════════════════════════════════
resource "local_file" "workflow_cicd" {
  filename        = "${path.module}/output/ci-cd/deploy_${local.env}.yml"
  file_permission = "0644"

  content = <<-EOT
    name: Deploy ${upper(local.env)}
    on:
      push:
        branches: [ ${local.env == "prod" ? "main" : local.env} ]
    jobs:
      deploy:
        runs-on: ubuntu-latest
        environment: ${local.env}
        steps:
          - uses: actions/checkout@v4
          - uses: hashicorp/setup-terraform@v3
          - run: terraform init
          - run: terraform apply -auto-approve
              -var="version_app=$\{\{ github.ref_name \}\}"
              -var="commit_sha=$\{\{ github.sha \}\}"
  EOT
}

# ════════════════════════════════════════════════════════════
#  VALIDATION & MONITORING — null_resource (J9)
# ════════════════════════════════════════════════════════════
resource "null_resource" "validation_deploiement" {
  triggers = {
    deploy_id = random_id.deploy_id.hex
    version   = var.version_app
    env       = local.env
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "============================================"
      echo "  Déploiement ${local.projet} [${local.env}]"
      echo "============================================"
      echo "  Version    : ${var.version_app}"
      echo "  Deploy ID  : ${random_id.deploy_id.hex}"
      echo "  Replicas   : ${local.env_config.replicas}"
      echo "  Tables     : ${length(local.tables)}"
      echo "  Sources    : ${length(local.sources)}"
      echo "  Timestamp  : ${local.ts}"
      echo "============================================"
    EOT
  }

  depends_on = [
    local_file.config_principale,
    local_file.init_sql,
    local_file.env_file,
  ]
}

# ════════════════════════════════════════════════════════════
#  DOCUMENTATION — Data catalogue (J8, J9 templatefile)
# ════════════════════════════════════════════════════════════
resource "local_file" "data_catalogue" {
  filename        = "${path.module}/output/${local.env}/DATA_CATALOGUE.md"
  file_permission = "0644"

  content = join("\n", [
    "# Data Catalogue — ${local.projet} [${local.env}]",
    "",
    "**Version :** ${var.version_app}  ",
    "**Deploy ID :** ${random_id.deploy_id.hex}  ",
    "**Généré le :** ${local.ts}",
    "",
    "---",
    "",
    "## Tables (${length(local.tables)})",
    "",
    join("\n", [for nom, t in local.tables :
      "### `${nom}`\n${t.desc}  \nIndex : ${length(t.index) > 0 ? join(", ", t.index) : "aucun"}\n"
    ]),
    "---",
    "",
    "## Sources (${length(local.sources)})",
    "",
    join("\n", [for nom, s in local.sources :
      "- **${nom}** : type `${s.type}` | schedule `${s.schedule}`"
    ]),
    "",
    "---",
    "Généré automatiquement par Terraform — Ne pas modifier.",
  ])

  depends_on = [null_resource.validation_deploiement]
}

# ════════════════════════════════════════════════════════════
#  MANIFEST FINAL (J9 — depends_on, lifecycle)
# ════════════════════════════════════════════════════════════
resource "local_file" "manifest_final" {
  filename        = "${path.module}/output/${local.env}/manifest.json"
  file_permission = "0644"

  content = jsonencode({
    meta = {
      projet    = local.projet
      env       = local.env
      version   = var.version_app
      deploy_id = random_id.deploy_id.hex
      ts        = local.ts
    }
    ressources = {
      tables       = length(local.tables)
      sources      = length(local.sources)
      modules      = length(local.modules_pipeline)
      fichiers     = 7
    }
    concepts_j1_a_j9 = [
      "J1 : resource, variable, output",
      "J2 : modules (config, pipeline, doc)",
      "J3 : workspaces (${local.env})",
      "J4 : for_each, count, for expressions",
      "J5 : CI/CD GitHub Actions",
      "J6 : provider Docker",
      "J7 : fmt, validate, tflint, checkov",
      "J8 : infra data, SQL généré, catalogue",
      "J9 : lifecycle, null_resource, moved",
      "J10 : tout combiné",
    ]
  })

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    local_file.data_catalogue,
    null_resource.validation_deploiement,
  ]
}
