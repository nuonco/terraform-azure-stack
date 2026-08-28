locals {
  prefix = local.nuon_install_id

  # The reserved var.roles keys "provision"/"maintenance"/"deprovision" let the
  # caller disable an operation role. Effectively disable-only: enabling a role
  # the app config grants nothing to would create an identity with no access,
  # so the grant check still applies.
  has_provision = lookup(var.roles, "provision", true) && (
    length(local.provision_actions) > 0 || length(local.provision_built_in_roles) > 0
  )
  has_maintenance = lookup(var.roles, "maintenance", true) && (
    length(local.maintenance_actions) > 0 || length(local.maintenance_built_in_roles) > 0
  )
  has_deprovision = lookup(var.roles, "deprovision", true) && (
    length(local.deprovision_actions) > 0 || length(local.deprovision_built_in_roles) > 0
  )

  # When the app declares no Azure roles at all, the stack creates no operation
  # identities and phone home reports empty client IDs. That is not a
  # misconfiguration: an empty identity ID is how Nuon selects the runner's
  # ambient system identity, which is how every Azure install behaved before
  # per-operation identities existed. Do not turn this into an error.
  use_operation_identities = (
    local.has_provision || local.has_maintenance || local.has_deprovision ||
    length(local.enabled_break_glass_roles) > 0 || length(local.enabled_custom_roles) > 0
  )

  # var.roles overrides are already folded into the `enabled` flag in stack.tf.
  enabled_break_glass_roles = { for k, v in local.break_glass_roles : k => v if v.enabled }
  enabled_custom_roles      = { for k, v in local.custom_roles : k => v if v.enabled }

  # Identity names. Managed identities allow 3–128 chars of alphanumerics,
  # hyphens and underscores, so unlike GCP's 30-char service accounts the
  # install ID and a legible suffix both fit and no hashing is needed. The
  # sanitize mirrors ctl-api's sanitizeAzureIdentitySuffix so a role name that
  # renders one identity under ARM renders the same one here.
  break_glass_identity_names = {
    for k in keys(local.enabled_break_glass_roles) :
    k => "${local.prefix}-bg-${substr(lower(replace(k, "/[^A-Za-z0-9-]/", "-")), 0, 40)}"
  }
  custom_identity_names = {
    for k in keys(local.enabled_custom_roles) :
    k => "${local.prefix}-custom-${substr(lower(replace(k, "/[^A-Za-z0-9-]/", "-")), 0, 40)}"
  }

  # Every identity gets a custom role definition, including one whose app config
  # grants no `actions`: the definition always carries */register/action so the
  # azurerm provider can register resource providers during a deploy. That
  # subscription-scoped action used to sit on the runner's system identity.
  register_action = "*/register/action"

  # Built-in role assignments, flattened to "{role key}:{built-in role}" keys so
  # each assignment is its own resource instance.
  break_glass_built_in_assignments = merge([
    for rk, rv in local.enabled_break_glass_roles : {
      for br in rv.built_in_roles : "${rk}:${br}" => { role_key = rk, built_in_role = br }
    }
  ]...)
  custom_built_in_assignments = merge([
    for rk, rv in local.enabled_custom_roles : {
      for br in rv.built_in_roles : "${rk}:${br}" => { role_key = rk, built_in_role = br }
    }
  ]...)

  # Key Vault names are capped at 24 characters, must start with a letter, and
  # cannot end in a hyphen — and they are globally unique across all of Azure.
  # Truncating the install ID is what the ARM install stack does
  # (scope.keyVaultNameInner), so the same install resolves to the same vault
  # whichever path provisioned it. trimsuffix covers a truncation that lands on
  # a hyphen, which Azure would reject.
  key_vault_name = trimsuffix(substr(local.prefix, 0, min(24, length(local.prefix))), "-")

  # Key Vault secret names allow only alphanumerics and hyphens. This mapping is
  # shared with the phone-home payload's secret URIs, so the two cannot drift.
  secret_kv_names = { for k in local.secret_names : k => replace(k, "_", "-") }

  # Every operation identity gets attached to the runner VMSS, which is how the
  # runner authenticates as one. Sorted for a stable plan.
  operation_identity_ids = sort(concat(
    local.has_provision ? [azurerm_user_assigned_identity.provision[0].id] : [],
    local.has_maintenance ? [azurerm_user_assigned_identity.maintenance[0].id] : [],
    local.has_deprovision ? [azurerm_user_assigned_identity.deprovision[0].id] : [],
    [for k in keys(local.enabled_break_glass_roles) : azurerm_user_assigned_identity.break_glass[k].id],
    [for k in keys(local.enabled_custom_roles) : azurerm_user_assigned_identity.custom[k].id],
  ))

  tags = {
    install_nuon_co_id = local.nuon_install_id
    org_nuon_co_id     = local.nuon_org_id
    app_nuon_co_id     = local.nuon_app_id
    managed_by         = "nuon"
  }
}
