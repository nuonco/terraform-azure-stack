##
## Nuon control-plane configuration.
##
## Runner details, role permissions, install inputs, and secret metadata are
## read from the Nuon API via the stack_config data source, keyed by install_id.
## This module has no tfvars-driven path — the control plane is the single
## source of truth.
##
## The read is authenticated: configure the stack provider with an api_token,
## or with org_id to exchange an ambient OIDC token in CI. The phone-home URL
## comes back in the response, so no per-stack-version secret is ever passed in
## as a variable.
##
## Non-secret values are read by indexing data.stack_config.this DIRECTLY —
## never via one()/try() over the whole object. Routing the object through a
## function collapses the sensitivity mark from the `secrets` attribute onto
## every sibling value, which would make unrelated outputs sensitive.
##

data "stack_config" "this" {
  install_id = var.install_id
}

locals {
  # identifiers
  nuon_install_id = data.stack_config.this.install_id
  nuon_org_id     = data.stack_config.this.org_id
  nuon_app_id     = data.stack_config.this.app_id

  # runner
  runner_id      = data.stack_config.this.runner_id
  runner_api_url = data.stack_config.this.runner_api_url
  phone_home_url = data.stack_config.this.phone_home_url

  # The runner container image the VM's cloud-init records as its initial
  # config. Unlike GCP, no static API token is served: the Azure runner
  # authenticates to Nuon as its own managed identity.
  container_image_url = data.stack_config.this.azure.container_image_url
  container_image_tag = data.stack_config.this.azure.container_image_tag

  # Caller override wins, then the control plane.
  location = var.location != "" ? var.location : data.stack_config.this.azure.location

  vpc_nested_template_url = data.stack_config.this.azure.vpc_nested_template_url

  # <install-id>-rg is what every other Nuon install path uses, and what the
  # control plane resolves the Key Vault, runner, and phone-home against.
  resource_group_name = var.resource_group_name != "" ? var.resource_group_name : "${local.nuon_install_id}-rg"

  # Caller override wins; then the Nuon app runner config; then the platform
  # default, which also covers a ctl-api that does not yet serve the field.
  runner_vm_size = (
    var.runner_vm_size != "" ? var.runner_vm_size :
    data.stack_config.this.azure.runner_vm_size != "" ? data.stack_config.this.azure.runner_vm_size :
    "Standard_D2s_v3"
  )

  # Operation-role grants. Azure splits permissions across two axes: `actions`
  # become a custom role definition this module creates, and `built_in_roles`
  # are assigned directly by name. A role may use either or both.
  provision_actions          = data.stack_config.this.azure.provision_actions
  provision_built_in_roles   = data.stack_config.this.azure.provision_built_in_roles
  maintenance_actions        = data.stack_config.this.azure.maintenance_actions
  maintenance_built_in_roles = data.stack_config.this.azure.maintenance_built_in_roles
  deprovision_actions        = data.stack_config.this.azure.deprovision_actions
  deprovision_built_in_roles = data.stack_config.this.azure.deprovision_built_in_roles

  # Roles as the control plane serves them, with var.roles layered on top:
  # a value set there wins over the control plane's enabled flag in both
  # directions, so a caller can turn a role off or switch one on. If the same
  # name appears in both maps, the override applies to both. Unknown keys are
  # rejected at plan time by the precondition on stack_phone_home.this.
  #
  # Served role names are templated with the install ID by the vendor, so
  # callers may key var.roles by the full name or by the short name with the
  # leading "<install-id>-" trimmed; the full name wins if both are set.
  role_name_prefix = "${var.install_id}-"
  break_glass_roles = {
    for k, v in data.stack_config.this.azure.break_glass_roles :
    k => merge(v, { enabled = lookup(var.roles, k, lookup(var.roles, trimprefix(k, local.role_name_prefix), v.enabled)) })
  }
  custom_roles = {
    for k, v in data.stack_config.this.azure.custom_roles :
    k => merge(v, { enabled = lookup(var.roles, k, lookup(var.roles, trimprefix(k, local.role_name_prefix), v.enabled)) })
  }

  # Reserved operation-role keys plus every served role name, in both full and
  # prefix-trimmed forms.
  known_role_keys = setunion(
    toset(["provision", "maintenance", "deprovision"]),
    keys(data.stack_config.this.azure.break_glass_roles),
    keys(data.stack_config.this.azure.custom_roles),
    toset([for k in keys(data.stack_config.this.azure.break_glass_roles) : trimprefix(k, local.role_name_prefix)]),
    toset([for k in keys(data.stack_config.this.azure.custom_roles) : trimprefix(k, local.role_name_prefix)]),
  )
  unknown_role_keys = setsubtract(keys(var.roles), local.known_role_keys)

  # What the precondition's error message displays: each role once, by its
  # short name, plus the reserved operation keys. known_role_keys (both forms)
  # remains the allowlist.
  display_role_keys = setunion(
    toset(["provision", "maintenance", "deprovision"]),
    toset([for k in keys(data.stack_config.this.azure.break_glass_roles) : trimprefix(k, local.role_name_prefix)]),
    toset([for k in keys(data.stack_config.this.azure.custom_roles) : trimprefix(k, local.role_name_prefix)]),
  )

  # inputs and secrets
  auto_generate_secrets = data.stack_config.this.auto_generate_secrets

  # The control plane serves the current value of every customer-facing input;
  # var.inputs is the caller's override and wins. The merged map is what the
  # stack applies with, and phone home reports it back so it becomes the
  # install's current inputs. Unknown keys are rejected at plan time by the
  # precondition on stack_phone_home.this.
  install_inputs = merge(
    data.stack_config.this.install_inputs,
    var.inputs,
  )

  unknown_input_keys = setsubtract(keys(var.inputs), keys(data.stack_config.this.install_inputs))

  # Required inputs must resolve to a non-empty value after the merge. Caught
  # here rather than downstream: an empty value would apply green, phone home,
  # and only fail later in the vendor's component deploys.
  missing_required_inputs = [
    for k in data.stack_config.this.required_input_names :
    k if lookup(local.install_inputs, k, "") == ""
  ]

  # Secret values supplied via var.secrets win over the data source. The marks
  # that try() collapses here are all genuinely sensitive, so the collapse is
  # correct in this block specifically.
  secret_names = toset(concat(
    keys(nonsensitive(data.stack_config.this.secrets)),
    keys(nonsensitive(var.secrets)),
  ))
  secrets = {
    for k in local.secret_names : k => {
      # coalesce() errors on an all-null/empty argument list, so it is wrapped:
      # a secret with no description anywhere must resolve to "", not blow up the
      # locals block before the preconditions below can report the real problem.
      description = try(coalesce(var.secrets[k].description, data.stack_config.this.secrets[k].description), "")
      required    = try(var.secrets[k].required, null) != null ? var.secrets[k].required : try(data.stack_config.this.secrets[k].required, false)
      value       = try(var.secrets[k].value, "") != "" ? var.secrets[k].value : try(data.stack_config.this.secrets[k].value, "")
    }
  }

  # A var.secrets key the app does not declare, mirroring unknown_input_keys:
  # secrets.tf would write it to the Key Vault under a name the vendor never
  # reads, so the typo has to fail the plan. Names only — a key is not itself a
  # secret value.
  unknown_secret_keys = nonsensitive(setsubtract(
    keys(nonsensitive(var.secrets)),
    keys(nonsensitive(data.stack_config.this.secrets)),
  ))

  # Required secrets must have a value: secrets.tf skips empty-valued optional
  # secrets entirely (an optional secret left unset shouldn't exist), which
  # without this check silently swallows a forgotten TF_VAR_ export for a
  # required one. Names only, so the list is safe to surface in an error message.
  missing_required_secrets = nonsensitive([
    for k, v in local.secrets : k if v.required && v.value == ""
  ])
}
