locals {
  # Client-ID maps for the phone-home payload. Empty when the app declares no
  # Azure roles, which the control plane reads as "use the runner's ambient
  # identity" — see the note on local.use_operation_identities.
  break_glass_identity_client_ids = { for k, v in azurerm_user_assigned_identity.break_glass : k => v.client_id }
  custom_identity_client_ids      = { for k, v in azurerm_user_assigned_identity.custom : k => v.client_id }

  # Each secret's Key Vault URI, built from the vault name and the shared name
  # mapping rather than read off the resources. That covers every secret the app
  # declares, including an optional one this apply did not create, which is what
  # the ARM install stack reports too.
  secret_ids = {
    for k in local.secret_names :
    "${k}_secret_id" => "https://${local.key_vault_name}.vault.azure.net/secrets/${local.secret_kv_names[k]}"
  }

  # Key names below match AzureStackOutputs' mapstructure tags in ctl-api. Subnet
  # lists are comma-joined strings, not JSON lists: the decoder splits them with
  # StringToSliceHookFunc(","), and an actual list would land in postgres HSTORE
  # as a space-separated string and decode to an empty list.
  #
  # deployment_location is deliberately absent — it records where an ARM
  # subscription-scoped deployment record lives, which has no Terraform analogue.
  phone_home_payload = merge({
    resource_group_id       = azurerm_resource_group.main.id
    resource_group_name     = azurerm_resource_group.main.name
    resource_group_location = azurerm_resource_group.main.location

    subscription_id        = data.azurerm_client_config.current.subscription_id
    subscription_tenant_id = data.azurerm_client_config.current.tenant_id

    network_id   = local.network.vnet_id
    network_name = local.network.vnet_name

    public_subnet_ids    = join(",", local.network.public_subnet_ids)
    public_subnet_names  = join(",", local.network.public_subnet_names)
    private_subnet_ids   = join(",", local.network.private_subnet_ids)
    private_subnet_names = join(",", local.network.private_subnet_names)

    key_vault_id   = azurerm_key_vault.main.id
    key_vault_name = azurerm_key_vault.main.name

    runner_identity_principal_id = local.runner_principal_id

    provision_identity_client_id    = local.has_provision ? azurerm_user_assigned_identity.provision[0].client_id : ""
    maintenance_identity_client_id  = local.has_maintenance ? azurerm_user_assigned_identity.maintenance[0].client_id : ""
    deprovision_identity_client_id  = local.has_deprovision ? azurerm_user_assigned_identity.deprovision[0].client_id : ""
    custom_identity_client_ids      = local.custom_identity_client_ids
    break_glass_identity_client_ids = local.break_glass_identity_client_ids

    install_inputs       = local.install_inputs
    custom_nested_stacks = local.custom_stack_outputs

    # Reported for parity with the AWS and GCP payloads. ctl-api does not read it
    # for Azure yet (AzureStackOutputs has no RunnerEnabled field), so disabling
    # the runner is not yet visible to the control plane.
    runner_enabled = var.runner_enabled
  }, local.secret_ids)
}

# Reported through the stack provider rather than a deploymentScripts resource
# running the Azure CLI. The request carries an Authorization header, and the
# provider owns retries and error reporting instead of a shell script inside the
# deployment.
#
# phone_home_url comes from the config data source — it embeds a per-stack-version
# identifier the caller has no other way to know, which is what lets this module
# take install_id alone.
#
# The resource lifecycle drives request_type: Create on first apply, Update when
# the payload changes, Delete on destroy. That replaces the deployTimestamp
# parameter, which forced a report on every deploy whether or not anything moved.
resource "stack_phone_home" "this" {
  depends_on = [
    module.network,
    azurerm_subscription_template_deployment.network,
    module.runner,
    azurerm_key_vault_secret.auto_generate,
    azurerm_key_vault_secret.customer,
    azurerm_key_vault_secret.telemetry_export_config,
    azurerm_role_assignment.provision_custom_role,
    azurerm_role_assignment.provision_built_in,
    azurerm_role_assignment.maintenance_custom_role,
    azurerm_role_assignment.maintenance_built_in,
    azurerm_role_assignment.deprovision_custom_role,
    azurerm_role_assignment.deprovision_built_in,
    azurerm_role_assignment.break_glass_custom_role,
    azurerm_role_assignment.break_glass_built_in,
    azurerm_role_assignment.custom_custom_role,
    azurerm_role_assignment.custom_built_in,
    azurerm_role_assignment.runner_legacy,
    azurerm_role_assignment.runner_register,
    azurerm_role_assignment.runner_key_vault,
    azurerm_role_assignment.runner_acr,
    azapi_resource.custom,
  ]

  install_id      = local.nuon_install_id
  phone_home_url  = local.phone_home_url
  phone_home_type = "azure"

  # Not part of the report: the authenticated phone-home URL is the same for
  # every version, so this is what makes a newly generated one show as a diff.
  stack_version_id = data.stack_config.this.stack_version_id

  payload = jsonencode(local.phone_home_payload)

  # The effective input values (control plane merged with var.inputs). The API
  # persists these as the install's current inputs, which is what makes the
  # inputs map a way to set input values — distinct from `payload`, which
  # records stack outputs.
  inputs = local.install_inputs

  # Hard preconditions rather than `check` blocks (which only warn, see
  # checks.tf): a typo'd input name would otherwise be silently dropped by the
  # API's own validation and the value never set.
  lifecycle {
    precondition {
      condition     = local.location != ""
      error_message = "no location resolved for this install: the Nuon control plane has none recorded and var.location is unset."
    }

    precondition {
      condition     = length(local.unknown_input_keys) == 0
      error_message = "var.inputs contains keys the app does not declare as customer-facing inputs: ${join(", ", local.unknown_input_keys)}. Declared inputs: ${join(", ", keys(data.stack_config.this.install_inputs))}."
    }

    precondition {
      condition     = length(local.missing_required_inputs) == 0
      error_message = "the app requires a value for these inputs: ${join(", ", local.missing_required_inputs)}."
    }

    precondition {
      condition     = length(local.unknown_secret_keys) == 0
      error_message = "var.secrets contains keys the app does not declare as customer-facing secrets: ${join(", ", local.unknown_secret_keys)}. Declared secrets: ${join(", ", keys(nonsensitive(data.stack_config.this.secrets)))}."
    }

    precondition {
      condition     = length(local.missing_required_secrets) == 0
      error_message = "the app requires a value for these secrets: ${join(", ", local.missing_required_secrets)}."
    }

    precondition {
      condition     = length(local.unknown_role_keys) == 0
      error_message = "var.roles contains keys that match no role: ${join(", ", local.unknown_role_keys)}. Valid keys: ${join(", ", local.display_role_keys)}."
    }

    precondition {
      condition     = length(local.custom_stacks) == 0 || data.stack_config.this.custom_stacks_template_url != ""
      error_message = "the app declares custom stacks, but the Nuon control plane did not provide a deployable custom-stacks template."
    }

    precondition {
      condition     = length(local.duplicate_custom_stack_names) == 0
      error_message = "custom stack names must be unique; duplicates: ${join(", ", local.duplicate_custom_stack_names)}."
    }

    precondition {
      condition     = length(local.duplicate_custom_stack_input_parameter_names) == 0
      error_message = "custom stack input parameters must map to unique top-level ARM parameters; duplicates: ${join(", ", local.duplicate_custom_stack_input_parameter_names)}."
    }

    precondition {
      condition     = length(local.missing_custom_stack_input_names) == 0
      error_message = "custom_stacks input_parameters reference inputs the install does not have: ${join(", ", local.missing_custom_stack_input_names)}. Known inputs: ${join(", ", keys(local.install_inputs))}."
    }
  }
}
