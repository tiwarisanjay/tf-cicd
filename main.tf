# setup k8s providers
provider "kubernetes" {
  config_path = "~/.kube/kind/cicd"
  alias       = "cicd"
}
provider "kubernetes" {
  config_path = "~/.kube/kind/admin"
  alias       = "admin"
}

# read the vault service principal
data "azuread_service_principal" "vault" {
  display_name = "bradfordwagner-vault"
}

## ADMIN resources
resource "kubernetes_namespace" "admin" {
  provider = kubernetes.admin
  for_each = toset(["vault", "argocd"])
  metadata {
    name = each.value
  }
}

resource "kubernetes_secret" "keyvault" {
  depends_on = [kubernetes_namespace.admin]
  provider   = kubernetes.admin
  metadata {
    name      = "keyvault"
    namespace = "vault"
  }
  data = {
    AZURE_TENANT_ID                = data.azuread_service_principal.vault.application_tenant_id
    AZURE_CLIENT_ID                = data.azuread_service_principal.vault.application_id
    AZURE_CLIENT_SECRET            = var.vault_sp_secret
    VAULT_AZUREKEYVAULT_VAULT_NAME = "bradfordwagner-vault"
    VAULT_AZUREKEYVAULT_KEY_NAME   = "generated-key"
  }
}

resource "kubernetes_secret" "admin_auth_config" {
  depends_on = [kubernetes_namespace.admin]
  provider   = kubernetes.admin
  metadata {
    name      = "k8s-auth-config"
    namespace = "vault"
  }
  data = {
    "cluster_name" = "admin"
    "ca"           = file("~/.kube/kind/internal/admin_ca")
    "server"       = file("~/.kube/kind/internal/admin_server")
    "role_id"      = var.role_id
    "secret_id"    = var.secret_id
  }
}

# based on: https://www.vaultproject.io/docs/platform/k8s/helm/run#protecting-sensitive-vault-configurations
resource "kubernetes_secret" "storage" {
  depends_on = [kubernetes_namespace.admin]
  provider   = kubernetes.admin
  metadata {
    name      = "storage"
    namespace = "vault"
  }
  data = {
    "config.hcl" = <<EOF
storage "azure" {
  accountName = "bradfordwagnervault"
  accountKey  = "${var.vault_storage_key}"
  container   = "backend"
  environment = "AzurePublicCloud"
}
EOF
  }
}

## End ADMIN resources

## CICD resources
resource "kubernetes_namespace" "cicd" {
  provider = kubernetes.cicd
  for_each = toset(values(var.namespaces))
  metadata {
    name = each.value
  }
}

resource "kubernetes_secret" "github" {
  depends_on = [kubernetes_namespace.cicd]
  provider   = kubernetes.cicd
  metadata {
    name      = "github-access-token"
    namespace = var.namespaces.events
  }
  data = {
    token = var.github_access_token
  }
}

resource "kubernetes_secret" "quay" {
  depends_on = [kubernetes_namespace.cicd]
  provider   = kubernetes.cicd
  metadata {
    name      = "bradfordwagner-kaniko-test-pull-secret"
    namespace = var.namespaces.workflows
  }
  data = {
    ".dockerconfigjson" = base64decode(var.quay_token)
  }
}

resource "kubernetes_secret" "cicd_auth_config" {
  depends_on = [kubernetes_namespace.admin]
  provider   = kubernetes.cicd
  metadata {
    name      = "k8s-auth-config"
    namespace = "vault"
  }
  data = {
    "cluster_name" = "cicd"
    "ca"           = file("~/.kube/kind/internal/cicd_ca")
    "server"       = file("~/.kube/kind/internal/cicd_server")
    "role_id"      = var.role_id
    "secret_id"    = var.secret_id
  }
}
## END CICD Resources
