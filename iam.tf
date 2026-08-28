##
## Operation identities and their grants.
##
## Azure expresses an operation identity as a user-assigned managed identity
## (UAMI) plus role assignments, rather than a role with a trust policy. There is
## no cross-tenant "assume" grant to render: the runner authenticates as one of
## these identities because the identity is attached to its scale set (see
## modules/runner). That means every identity created here is reachable by
## anything running on the runner, break-glass included — which is exactly how
## the ARM install stack behaves, and why var.roles is the control for narrowing
## it.
##
## Each identity gets grants along two axes, mirroring the app config:
##   - `actions`         -> a custom role definition, at SUBSCRIPTION scope
##   - `built_in_roles`  -> direct assignments of Azure built-in roles, at
##                          RESOURCE GROUP scope
##
## The scopes are not interchangeable. Custom definitions are subscription-scoped
## because they must carry */register/action, which is a subscription-level
## action; built-in assignments stay at resource-group scope so an install cannot
## grant itself rights outside its own group.
##

data "azurerm_subscription" "current" {}

###############################################################################
# Provision identity
###############################################################################

resource "azurerm_user_assigned_identity" "provision" {
  count               = local.has_provision ? 1 : 0
  name                = "${local.prefix}-provision"
  resource_group_name = azurerm_resource_group.main.name
  location            = local.location
  tags                = local.tags
}

resource "azurerm_role_definition" "provision" {
  count = local.has_provision ? 1 : 0
  name  = "${local.prefix}-provision-role"
  scope = data.azurerm_subscription.current.id

  description       = "Nuon per-operation runner identity role"
  assignable_scopes = [data.azurerm_subscription.current.id]

  permissions {
    actions = concat([local.register_action], local.provision_actions)
  }
}

resource "azurerm_role_assignment" "provision_custom_role" {
  count              = local.has_provision ? 1 : 0
  scope              = data.azurerm_subscription.current.id
  role_definition_id = azurerm_role_definition.provision[0].role_definition_resource_id
  principal_id       = azurerm_user_assigned_identity.provision[0].principal_id
  principal_type     = "ServicePrincipal"
}

resource "azurerm_role_assignment" "provision_built_in" {
  # Gated on has_provision too: var.roles can disable the role while the
  # control plane still serves its built-in roles, and the identity would not exist.
  for_each           = local.has_provision ? toset(local.provision_built_in_roles) : toset([])
  scope              = azurerm_resource_group.main.id
  role_definition_id = "${data.azurerm_subscription.current.id}/providers/Microsoft.Authorization/roleDefinitions/${each.value}"
  principal_id       = azurerm_user_assigned_identity.provision[0].principal_id
  principal_type     = "ServicePrincipal"
}

###############################################################################
# Maintenance identity
###############################################################################

resource "azurerm_user_assigned_identity" "maintenance" {
  count               = local.has_maintenance ? 1 : 0
  name                = "${local.prefix}-maintenance"
  resource_group_name = azurerm_resource_group.main.name
  location            = local.location
  tags                = local.tags
}

resource "azurerm_role_definition" "maintenance" {
  count = local.has_maintenance ? 1 : 0
  name  = "${local.prefix}-maintenance-role"
  scope = data.azurerm_subscription.current.id

  description       = "Nuon per-operation runner identity role"
  assignable_scopes = [data.azurerm_subscription.current.id]

  permissions {
    actions = concat([local.register_action], local.maintenance_actions)
  }
}

resource "azurerm_role_assignment" "maintenance_custom_role" {
  count              = local.has_maintenance ? 1 : 0
  scope              = data.azurerm_subscription.current.id
  role_definition_id = azurerm_role_definition.maintenance[0].role_definition_resource_id
  principal_id       = azurerm_user_assigned_identity.maintenance[0].principal_id
  principal_type     = "ServicePrincipal"
}

resource "azurerm_role_assignment" "maintenance_built_in" {
  # Gated on has_maintenance too: var.roles can disable the role while the
  # control plane still serves its built-in roles, and the identity would not exist.
  for_each           = local.has_maintenance ? toset(local.maintenance_built_in_roles) : toset([])
  scope              = azurerm_resource_group.main.id
  role_definition_id = "${data.azurerm_subscription.current.id}/providers/Microsoft.Authorization/roleDefinitions/${each.value}"
  principal_id       = azurerm_user_assigned_identity.maintenance[0].principal_id
  principal_type     = "ServicePrincipal"
}

###############################################################################
# Deprovision identity
###############################################################################

resource "azurerm_user_assigned_identity" "deprovision" {
  count               = local.has_deprovision ? 1 : 0
  name                = "${local.prefix}-deprovision"
  resource_group_name = azurerm_resource_group.main.name
  location            = local.location
  tags                = local.tags
}

resource "azurerm_role_definition" "deprovision" {
  count = local.has_deprovision ? 1 : 0
  name  = "${local.prefix}-deprovision-role"
  scope = data.azurerm_subscription.current.id

  description       = "Nuon per-operation runner identity role"
  assignable_scopes = [data.azurerm_subscription.current.id]

  permissions {
    actions = concat([local.register_action], local.deprovision_actions)
  }
}

resource "azurerm_role_assignment" "deprovision_custom_role" {
  count              = local.has_deprovision ? 1 : 0
  scope              = data.azurerm_subscription.current.id
  role_definition_id = azurerm_role_definition.deprovision[0].role_definition_resource_id
  principal_id       = azurerm_user_assigned_identity.deprovision[0].principal_id
  principal_type     = "ServicePrincipal"
}

resource "azurerm_role_assignment" "deprovision_built_in" {
  # Gated on has_deprovision too: var.roles can disable the role while the
  # control plane still serves its built-in roles, and the identity would not exist.
  for_each           = local.has_deprovision ? toset(local.deprovision_built_in_roles) : toset([])
  scope              = azurerm_resource_group.main.id
  role_definition_id = "${data.azurerm_subscription.current.id}/providers/Microsoft.Authorization/roleDefinitions/${each.value}"
  principal_id       = azurerm_user_assigned_identity.deprovision[0].principal_id
  principal_type     = "ServicePrincipal"
}

###############################################################################
# Break-glass identities (dynamic, one per enabled role)
###############################################################################

resource "azurerm_user_assigned_identity" "break_glass" {
  for_each            = local.enabled_break_glass_roles
  name                = local.break_glass_identity_names[each.key]
  resource_group_name = azurerm_resource_group.main.name
  location            = local.location
  tags                = local.tags
}

resource "azurerm_role_definition" "break_glass" {
  for_each = local.enabled_break_glass_roles
  name     = "${local.break_glass_identity_names[each.key]}-role"
  scope    = data.azurerm_subscription.current.id

  description       = "Nuon per-operation runner identity role"
  assignable_scopes = [data.azurerm_subscription.current.id]

  permissions {
    actions = concat([local.register_action], each.value.actions)
  }
}

resource "azurerm_role_assignment" "break_glass_custom_role" {
  for_each           = local.enabled_break_glass_roles
  scope              = data.azurerm_subscription.current.id
  role_definition_id = azurerm_role_definition.break_glass[each.key].role_definition_resource_id
  principal_id       = azurerm_user_assigned_identity.break_glass[each.key].principal_id
  principal_type     = "ServicePrincipal"
}

resource "azurerm_role_assignment" "break_glass_built_in" {
  for_each           = local.break_glass_built_in_assignments
  scope              = azurerm_resource_group.main.id
  role_definition_id = "${data.azurerm_subscription.current.id}/providers/Microsoft.Authorization/roleDefinitions/${each.value.built_in_role}"
  principal_id       = azurerm_user_assigned_identity.break_glass[each.value.role_key].principal_id
  principal_type     = "ServicePrincipal"
}

###############################################################################
# Custom identities (dynamic, one per enabled role)
###############################################################################

resource "azurerm_user_assigned_identity" "custom" {
  for_each            = local.enabled_custom_roles
  name                = local.custom_identity_names[each.key]
  resource_group_name = azurerm_resource_group.main.name
  location            = local.location
  tags                = local.tags
}

resource "azurerm_role_definition" "custom" {
  for_each = local.enabled_custom_roles
  name     = "${local.custom_identity_names[each.key]}-role"
  scope    = data.azurerm_subscription.current.id

  description       = "Nuon per-operation runner identity role"
  assignable_scopes = [data.azurerm_subscription.current.id]

  permissions {
    actions = concat([local.register_action], each.value.actions)
  }
}

resource "azurerm_role_assignment" "custom_custom_role" {
  for_each           = local.enabled_custom_roles
  scope              = data.azurerm_subscription.current.id
  role_definition_id = azurerm_role_definition.custom[each.key].role_definition_resource_id
  principal_id       = azurerm_user_assigned_identity.custom[each.key].principal_id
  principal_type     = "ServicePrincipal"
}

resource "azurerm_role_assignment" "custom_built_in" {
  for_each           = local.custom_built_in_assignments
  scope              = azurerm_resource_group.main.id
  role_definition_id = "${data.azurerm_subscription.current.id}/providers/Microsoft.Authorization/roleDefinitions/${each.value.built_in_role}"
  principal_id       = azurerm_user_assigned_identity.custom[each.value.role_key].principal_id
  principal_type     = "ServicePrincipal"
}

###############################################################################
# Runner system-identity grants
###############################################################################

locals {
  # Built-in role GUIDs. Named here rather than inline so the grant blocks below
  # read as policy rather than as GUID soup.
  role_contributor       = "b24988ac-6180-42a0-ab88-20f7382dd24c"
  role_rbac_admin        = "f58310d9-a9f6-439a-9e8d-f62e7b41a168"
  role_aks_cluster_admin = "b1ff04bb-8a4e-4dc4-8eb5-8693973ce19b"
  role_kv_secrets_user   = "4633458b-17de-408a-b874-0445c86b69e6"
  role_acr_pull          = "7f951dda-4ed3-4680-a7ca-43fe172d538d"
  role_acr_push          = "8311e382-0749-4cb8-b61a-304f252e45ec"

  runner_principal_id = var.runner_enabled ? module.runner[0].vmss_principal_id : ""

  # The broad grants the runner's own identity carries when no per-operation
  # identity exists to hold them. Once operation identities are in play the
  # system identity is stripped of deploy rights and keeps only the secret- and
  # image-sync grants below.
  legacy_runner_grants = var.runner_enabled && !local.use_operation_identities ? toset([
    local.role_contributor,
    local.role_rbac_admin,
    local.role_aks_cluster_admin,
  ]) : toset([])

  # Kept on the system identity in both modes: secret sync and image sync run as
  # the runner's ambient identity, never as a per-operation one.
  runner_acr_grants = var.runner_enabled ? toset([local.role_acr_pull, local.role_acr_push]) : toset([])
}

resource "azurerm_role_assignment" "runner_legacy" {
  for_each           = local.legacy_runner_grants
  scope              = azurerm_resource_group.main.id
  role_definition_id = "${data.azurerm_subscription.current.id}/providers/Microsoft.Authorization/roleDefinitions/${each.value}"
  principal_id       = local.runner_principal_id
  principal_type     = "ServicePrincipal"
}

# */register/action for the runner's own identity, for the same reason the
# per-operation definitions carry it: registering a resource provider is a
# subscription-level action. Only needed in the legacy mode, where the system
# identity is what runs deploys.
resource "azurerm_role_definition" "runner_register" {
  count = var.runner_enabled && !local.use_operation_identities ? 1 : 0
  name  = "${local.prefix}-runner-resource-provider-register-role"
  scope = data.azurerm_subscription.current.id

  description       = "Allows the runner to register Azure resource providers"
  assignable_scopes = [data.azurerm_subscription.current.id]

  permissions {
    actions = [local.register_action]
  }
}

resource "azurerm_role_assignment" "runner_register" {
  count              = var.runner_enabled && !local.use_operation_identities ? 1 : 0
  scope              = data.azurerm_subscription.current.id
  role_definition_id = azurerm_role_definition.runner_register[0].role_definition_resource_id
  principal_id       = local.runner_principal_id
  principal_type     = "ServicePrincipal"
}

resource "azurerm_role_assignment" "runner_key_vault" {
  count              = var.runner_enabled ? 1 : 0
  scope              = azurerm_key_vault.main.id
  role_definition_id = "${data.azurerm_subscription.current.id}/providers/Microsoft.Authorization/roleDefinitions/${local.role_kv_secrets_user}"
  principal_id       = local.runner_principal_id
  principal_type     = "ServicePrincipal"
}

resource "azurerm_role_assignment" "runner_acr" {
  for_each           = local.runner_acr_grants
  scope              = azurerm_resource_group.main.id
  role_definition_id = "${data.azurerm_subscription.current.id}/providers/Microsoft.Authorization/roleDefinitions/${each.value}"
  principal_id       = local.runner_principal_id
  principal_type     = "ServicePrincipal"
}
