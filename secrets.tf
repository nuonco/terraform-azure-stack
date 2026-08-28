##
## Secrets.
##
## Values land in the install's Key Vault. Key Vault secret names allow only
## alphanumerics and hyphens, so an app-config name's underscores are rewritten
## by local.secret_kv_names — the same mapping the phone-home payload uses to
## build each secret's URI, so the two cannot drift.
##
## Access is granted by role assignment, not access policy: the vault is
## RBAC-authorized (main.tf). The runner's system identity holds Key Vault
## Secrets User over the whole vault (iam.tf), which is what secret sync reads
## through, so there are no per-secret grants here.
##

###############################################################################
# Auto-generated secrets
###############################################################################

resource "random_password" "auto_generate" {
  for_each = toset(local.auto_generate_secrets)
  length   = 63
  special  = false

  keepers = {
    secret_name = each.key
    install_id  = local.nuon_install_id
  }
}

resource "azurerm_key_vault_secret" "auto_generate" {
  for_each     = toset(local.auto_generate_secrets)
  name         = local.secret_kv_names[each.key]
  value        = random_password.auto_generate[each.key].result
  key_vault_id = azurerm_key_vault.main.id

  # The vault is RBAC-authorized, so the identity running Terraform needs its
  # own Key Vault Secrets Officer grant before it can write. Without this the
  # write races the caller's grant and fails with a 403 on a first apply.
  depends_on = [azurerm_role_assignment.terraform_key_vault_officer]

  lifecycle {
    ignore_changes = [value]
  }
}

###############################################################################
# Customer-provided secrets
###############################################################################

# Skip optional secrets left unset — an optional secret with no value shouldn't
# be created at all. Required secrets are always created: if one is left empty,
# Azure rejects the empty value and surfaces the error instead of silently
# skipping a secret the install depends on.
locals {
  customer_secret_keys = toset(nonsensitive([for k, v in local.secrets : k if v.value != "" || v.required]))
}

resource "azurerm_key_vault_secret" "customer" {
  for_each     = local.customer_secret_keys
  name         = local.secret_kv_names[each.key]
  value        = local.secrets[each.key].value
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_role_assignment.terraform_key_vault_officer]

  lifecycle {
    ignore_changes = [value]
  }
}

###############################################################################
# Telemetry export configuration
###############################################################################

# Created empty and written to out of band, matching the other install-stack
# paths: the runner reads it, Nuon populates it.
resource "azurerm_key_vault_secret" "telemetry_export_config" {
  name         = "telemetry-export-config"
  value        = "{}"
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_role_assignment.terraform_key_vault_officer]

  lifecycle {
    ignore_changes = [value]
  }
}

###############################################################################
# Terraform's own write access
###############################################################################

# An RBAC-authorized vault grants nothing to its creator, so the identity
# applying this module cannot write the secrets above until it holds a role on
# the vault. Scoped to the vault only, and to Secrets Officer rather than
# anything broader.
resource "azurerm_role_assignment" "terraform_key_vault_officer" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}
