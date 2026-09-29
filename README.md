# 🏆 Jour 10 / 10 — Terraform : Projet Final

> **Série : 10 Days of Terraform** · Jour 10/10 — DERNIER JOUR 🎉  
> Tout ce qu'on a appris en 10 jours réuni en une infrastructure data complète

---

## 📁 Fichiers du projet

```
day-10-projet-final/
│
├── main.tf              ← Infrastructure complète J1→J9
├── variables.tf         ← Variables avec validations semver
├── outputs.tf           ← Résumé complet du déploiement
├── output/              ← Généré par Terraform
│   └── dev/
│       ├── config.json
│       ├── sql/init.sql
│       ├── pipelines/api.json · sftp.json · db_erp.json
│       ├── .env
│       ├── DATA_CATALOGUE.md
│       └── manifest.json
│   └── ci-cd/
│       └── deploy_dev.yml
└── README.md
```

---

## 🎓 Ce que ce projet combine

| Jour | Concept | Présent dans le projet final |
|------|---------|------------------------------|
| J1 | resource, variable, output | ✓ Structure de base |
| J2 | Modules | ✓ Sections config/sql/pipeline/env/cicd/doc |
| J3 | Workspaces | ✓ `terraform.workspace` pour l'env |
| J4 | for_each, for expressions, conditions | ✓ Sources, tables, configs |
| J5 | CI/CD GitHub Actions | ✓ Workflow généré par env |
| J6 | Provider Docker | ✓ Pattern réutilisé |
| J7 | Validations, fmt, validate | ✓ regex semver, enum env |
| J8 | SQL généré, data catalogue | ✓ init.sql + DATA_CATALOGUE.md |
| J9 | lifecycle, null_resource, time, depends_on | ✓ Sur toutes les resources critiques |

---

## 🚀 ÉTAPE 1 — Préparer les fichiers

```bash
mkdir -p jour10-terraform/output
cd jour10-terraform/

# Copier les fichiers :
# main_j10.tf       → main.tf
# variables_j10.tf  → variables.tf
# outputs_j10.tf    → outputs.tf

cat > .gitignore << 'EOF'
.terraform/
.terraform.lock.hcl
terraform.tfstate*
output/
EOF
```

---

## 🚀 ÉTAPE 2 — Initialiser

```bash
terraform init

# Télécharge les 4 providers :
# - hashicorp/local
# - hashicorp/random
# - hashicorp/null
# - hashicorp/time
```

---

## 🚀 ÉTAPE 3 — Plan et Apply sur dev

```bash
terraform plan

# Résultat :
# random_id.deploy_id                           will be created
# random_password.db_password                   will be created
# time_rotating.rotation_secrets                will be created
# local_file.config_principale                  will be created
# local_file.init_sql                           will be created
# local_file.config_source["api"]               will be created
# local_file.config_source["sftp"]              will be created
# local_file.config_source["db_erp"]            will be created
# local_file.env_file                           will be created
# local_file.workflow_cicd                      will be created
# null_resource.validation_deploiement          will be created
# local_file.data_catalogue                     will be created
# local_file.manifest_final                     will be created
# Plan: 13 to add, 0 to change, 0 to destroy.

terraform apply -auto-approve
# → voir la validation s'exécuter dans les logs
```

---

## 🚀 ÉTAPE 4 — Vérifier tous les fichiers générés

```bash
# Config principale
cat output/dev/config.json | python3 -m json.tool

# Script SQL
cat output/dev/sql/init.sql

# Config pipeline API
cat output/dev/pipelines/api.json | python3 -m json.tool

# Data catalogue
cat output/dev/DATA_CATALOGUE.md

# Manifest final
cat output/dev/manifest.json | python3 -m json.tool

# Workflow CI/CD généré
cat output/ci-cd/deploy_dev.yml

# Variables d'environnement
cat output/dev/.env
```

---

## 🚀 ÉTAPE 5 — Voir les outputs

```bash
terraform output

# resume_deploiement = {
#   deploy_id  = "a1b2c3d4"
#   env        = "dev"
#   nb_sources = 3
#   nb_tables  = 4
#   projet     = "etl_portfolio"
#   replicas   = 1
#   version    = "1.0.0"
# }

# Mot de passe généré (sensitive)
terraform output -raw db_password

# Prochaine rotation des secrets
terraform output rotation_secrets
```

---

## 🚀 ÉTAPE 6 — Déployer sur staging et prod

```bash
# Staging via workspace (J3)
terraform workspace new staging
terraform apply -var="version_app=1.0.0" -auto-approve
# → output/staging/ créé avec batch_size=500, replicas=2

# Prod via workspace
terraform workspace new prod
terraform apply -var="version_app=1.0.0" -auto-approve
# → output/prod/ créé avec batch_size=1000, replicas=3

# Comparer les configs
cat output/dev/config.json  | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['infrastructure'])"
cat output/prod/config.json | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['infrastructure'])"
```

---

## 🔑 ÉTAPE 7 — Changer la version → nouveau deploy_id

```bash
terraform apply -var="version_app=2.0.0" -auto-approve

# random_id.deploy_id doit être recréé (keepers.version a changé)
# Tous les fichiers qui utilisent deploy_id sont mis à jour

terraform output -json resume_deploiement | python3 -m json.tool
# → deploy_id : nouvelle valeur
# → version   : "2.0.0"
```

---

## 🔑 ÉTAPE 8 — Ajouter une table sans tout recréer

```hcl
# Dans main.tf, ajouter dans locals.tables :
alertes = { desc = "Alertes pipeline", index = ["date"] }
```

```bash
terraform plan
# → local_file.init_sql      : 1 to change (SQL régénéré)
# → local_file.data_catalogue: 1 to change (catalogue mis à jour)
# → local_file.manifest_final: 1 to change
# Plan: 0 to add, 3 to change, 0 to destroy.

terraform apply -auto-approve
# init.sql contient maintenant CREATE TABLE alertes ✓
```

---

## 🚀 ÉTAPE 9 — Tests (J7)

```bash
# Format
terraform fmt -check -recursive

# Validation
terraform validate

# Test variable invalide
terraform plan -var="version_app=v1"
# Error: Format semver : X.Y.Z ✓

terraform plan -var="environnement=invalid"
# Error: Valeurs : dev, staging, prod. ✓

# Idempotence
terraform apply -auto-approve
terraform plan
# → No changes. Infrastructure is up-to-date. ✓
```

---

## 🚀 ÉTAPE 10 — Nettoyer

```bash
# Retourner sur le workspace default
terraform workspace select default

# Détruire
terraform destroy -auto-approve

# Supprimer les workspaces
terraform workspace delete staging
terraform workspace delete prod
```



---

⭐ **Si ce projet t'aide, mets une étoile !**
