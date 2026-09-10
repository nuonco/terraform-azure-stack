# A vendor who customised their ARM virtual network has components that depend on
# the subnets and NSGs it adds, so building this module's network instead would
# leave them missing on the Terraform path. The template is subscription-scoped
# and creates its own network resource group.
#
# azapi rather than azurerm_subscription_template_deployment: that resource pins
# API version 2020-06-01, which rejects languageVersion 2.0 symbolic resources.
resource "azapi_resource" "network" {
  count = local.vpc_nested_template_url != "" ? 1 : 0

  type      = "Microsoft.Resources/deployments@2022-09-01"
  name      = "${local.prefix}-network"
  parent_id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  location  = local.location

  body = {
    properties = {
      mode = "Incremental"
      templateLink = {
        uri = local.vpc_nested_template_url
      }
      parameters = {
        nuonInstallID = { value = local.nuon_install_id }
        location      = { value = local.location }
      }
    }
  }

  response_export_values = {
    outputs = "properties.outputs"
  }
}

locals {
  network_from_template = length(azapi_resource.network) > 0

  network_template_outputs = try(azapi_resource.network[0].output.outputs, {})

  # Outputs the vendor template declares beyond the fixed contract below. ARM
  # passes these through as install_stack.outputs.vnet_<snake_case name> and app
  # configs read them, so dropping them here breaks those templates.
  network_contract_outputs = toset([
    "vnetId", "vnetName",
    "runnerSubnetId", "runnerSubnetName",
    "publicSubnet1Id", "publicSubnet1Name",
    "publicSubnet2Id", "publicSubnet2Name",
    "publicSubnet3Id", "publicSubnet3Name",
    "privateSubnet1Id", "privateSubnet1Name",
    "privateSubnet2Id", "privateSubnet2Name",
    "privateSubnet3Id", "privateSubnet3Name",
    "publicSubnetIds", "publicSubnetNames",
    "privateSubnetIds", "privateSubnetNames",
  ])

  network_passthrough_outputs = {
    for name, value in local.network_template_outputs :
    "vnet_${lower(replace(replace(name, "/([a-z0-9])([A-Z])/", "$${1}_$${2}"), "/[^A-Za-z0-9]/", "_"))}" => try(tostring(value.value), "")
    if !contains(local.network_contract_outputs, name)
  }

  network = local.network_from_template ? {
    vnet_id              = try(local.network_template_outputs.vnetId.value, "")
    vnet_name            = try(local.network_template_outputs.vnetName.value, "")
    public_subnet_ids    = compact(split(",", try(local.network_template_outputs.publicSubnetIds.value, "")))
    public_subnet_names  = compact(split(",", try(local.network_template_outputs.publicSubnetNames.value, "")))
    private_subnet_ids   = compact(split(",", try(local.network_template_outputs.privateSubnetIds.value, "")))
    private_subnet_names = compact(split(",", try(local.network_template_outputs.privateSubnetNames.value, "")))
    runner_subnet_id     = try(local.network_template_outputs.runnerSubnetId.value, "")
    runner_subnet_name   = try(local.network_template_outputs.runnerSubnetName.value, "")
    } : {
    vnet_id              = one(module.network[*].vnet_id)
    vnet_name            = one(module.network[*].vnet_name)
    public_subnet_ids    = try(one(module.network[*].public_subnet_ids), [])
    public_subnet_names  = try(one(module.network[*].public_subnet_names), [])
    private_subnet_ids   = try(one(module.network[*].private_subnet_ids), [])
    private_subnet_names = try(one(module.network[*].private_subnet_names), [])
    runner_subnet_id     = one(module.network[*].runner_subnet_id)
    runner_subnet_name   = one(module.network[*].runner_subnet_name)
  }
}
