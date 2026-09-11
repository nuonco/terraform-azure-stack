##
## The install resource group and Key Vault, plus the network and runner
## submodules.
##
## Unlike the ARM install stack, the resource group is created here rather than
## being a customer prerequisite: Terraform has no equivalent of ARM's
## subscription-vs-resource-group deployment scopes, so there is no reason to
## make the group someone else's job. The name still defaults to
## <install-id>-rg, which is what the control plane resolves against.
##

resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = local.location
  tags     = local.tags
}

# RBAC rather than access policies: the runner's Key Vault Secrets User grant
# (iam.tf) is a role assignment, and a vault cannot mix the two models.
resource "azurerm_key_vault" "main" {
  name                = local.key_vault_name
  resource_group_name = azurerm_resource_group.main.name
  location            = local.location
  tags                = local.tags

  tenant_id = data.azurerm_client_config.current.tenant_id
  sku_name  = "standard"

  rbac_authorization_enabled = true

  # Soft delete is not optional on Azure any more, so the only real choice is
  # whether a destroyed install's vault name is reusable. Purge protection would
  # hold the name for 90 days and block a reprovision under the same install ID,
  # so it stays off and the provider purges on destroy (see the provider
  # `features` block callers must set).
  purge_protection_enabled   = false
  soft_delete_retention_days = 7
}

data "azurerm_client_config" "current" {}

module "network" {
  source = "./modules/network"
  count  = local.vpc_nested_template_url != "" ? 0 : 1

  prefix              = local.prefix
  resource_group_name = azurerm_resource_group.main.name
  location            = local.location
  tags                = local.tags

  vnet_cidr            = var.vnet_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  runner_subnet_cidr   = var.runner_subnet_cidr
}

module "runner" {
  source = "./modules/runner"
  count  = var.runner_enabled ? 1 : 0

  depends_on = [azurerm_lb_rule.telemetry]

  prefix              = local.prefix
  resource_group_name = azurerm_resource_group.main.name
  location            = local.location
  tags                = local.tags

  vm_size                                = local.runner_vm_size
  runner_subnet_id                       = local.network.runner_subnet_id
  load_balancer_backend_address_pool_ids = local.telemetry_ingress_enabled ? [azurerm_lb_backend_address_pool.telemetry[0].id] : []

  # Attaching the operation identities is what lets the runner authenticate as
  # them; see iam.tf.
  user_assigned_identity_ids = local.operation_identity_ids

  nuon_install_id     = local.nuon_install_id
  runner_id           = local.runner_id
  runner_api_url      = local.runner_api_url
  container_image_url = local.container_image_url
  container_image_tag = local.container_image_tag
}
