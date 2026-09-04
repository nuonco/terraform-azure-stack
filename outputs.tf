# Output names mirror the phone-home payload so anything reading
# `terraform output` or `nuon.install_stack.outputs.*` sees the same key set.

output "resource_group_id" {
  value = azurerm_resource_group.main.id
}

output "resource_group_name" {
  value = azurerm_resource_group.main.name
}

output "resource_group_location" {
  value = azurerm_resource_group.main.location
}

output "subscription_id" {
  value = data.azurerm_client_config.current.subscription_id
}

output "subscription_tenant_id" {
  value = data.azurerm_client_config.current.tenant_id
}

output "network_id" {
  value = module.network.vnet_id
}

output "network_name" {
  value = module.network.vnet_name
}

output "public_subnet_ids" {
  value = module.network.public_subnet_ids
}

output "public_subnet_names" {
  value = module.network.public_subnet_names
}

output "private_subnet_ids" {
  value = module.network.private_subnet_ids
}

output "private_subnet_names" {
  value = module.network.private_subnet_names
}

output "runner_subnet_id" {
  value = module.network.runner_subnet_id
}

output "runner_subnet_name" {
  value = module.network.runner_subnet_name
}

output "key_vault_id" {
  value = azurerm_key_vault.main.id
}

output "key_vault_name" {
  value = azurerm_key_vault.main.name
}

output "key_vault_uri" {
  value = azurerm_key_vault.main.vault_uri
}

output "runner_identity_principal_id" {
  value       = local.runner_principal_id
  description = "Principal ID of the runner scale set's system-assigned identity. Secret sync and image sync run as this identity. Empty when the runner is disabled."
}

output "provision_identity_client_id" {
  value       = local.has_provision ? azurerm_user_assigned_identity.provision[0].client_id : ""
  description = "Client ID of the provision identity. Empty when the app declares no Azure provision role, which selects the runner's ambient identity instead."
}

output "maintenance_identity_client_id" {
  value       = local.has_maintenance ? azurerm_user_assigned_identity.maintenance[0].client_id : ""
  description = "Client ID of the maintenance identity. Empty when the app declares no Azure maintenance role."
}

output "deprovision_identity_client_id" {
  value       = local.has_deprovision ? azurerm_user_assigned_identity.deprovision[0].client_id : ""
  description = "Client ID of the deprovision identity. Empty when the app declares no Azure deprovision role."
}

output "break_glass_identity_client_ids" {
  value       = local.break_glass_identity_client_ids
  description = "Map of break-glass role name to managed identity client ID."
}

output "custom_identity_client_ids" {
  value       = local.custom_identity_client_ids
  description = "Map of custom role name to managed identity client ID."
}

output "install_inputs" {
  value       = local.install_inputs
  description = "Effective customer-facing input values: control-plane values merged with var.inputs overrides, as reported back to Nuon."
}

output "custom_nested_stacks" {
  value       = local.custom_stack_outputs
  description = "Outputs of custom ARM deployments, keyed by stack name."
}

output "sensitive_input_names" {
  value       = data.stack_config.this.sensitive_input_names
  description = "Names of inputs the app marks sensitive. The install_inputs map itself is not marked sensitive (Terraform maps are all-or-nothing); use this list to handle those values carefully downstream."
}

output "secret_ids" {
  value       = local.secret_ids
  description = "Map of <secret_name>_secret_id to Key Vault secret URIs."
}

output "runner_enabled" {
  value = var.runner_enabled
}
