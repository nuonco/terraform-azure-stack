locals {
  custom_stacks      = data.stack_config.this.custom_stacks
  custom_stack_names = [for stack in local.custom_stacks : stack.name]
  duplicate_custom_stack_names = toset([
    for name in local.custom_stack_names : name
    if length([for candidate in local.custom_stack_names : candidate if candidate == name]) > 1
  ])
  custom_stack_input_parameters = merge({}, [
    for stack in local.custom_stacks : {
      for parameter_name, input_name in stack.input_parameters :
      parameter_name => { value = lookup(local.install_inputs, input_name, "") }
    }
  ]...)
  custom_stack_input_parameter_names = flatten([
    for stack in local.custom_stacks : [for name in keys(stack.input_parameters) : lower(name)]
  ])
  duplicate_custom_stack_input_parameter_names = toset([
    for name in local.custom_stack_input_parameter_names : name
    if length([for candidate in local.custom_stack_input_parameter_names : candidate if candidate == name]) > 1
  ])
  missing_custom_stack_input_names = tolist(setsubtract(
    toset(flatten([for stack in local.custom_stacks : values(stack.input_parameters)])),
    toset(keys(local.install_inputs)),
  ))

  custom_stack_template_outputs = length(azapi_resource.custom) > 0 ? azapi_resource.custom[0].output.outputs : {}
  custom_stack_template_outputs_by_lower_name = {
    for name, value in local.custom_stack_template_outputs : lower(name) => value
  }
  custom_stack_outputs = {
    for stack in local.custom_stacks : stack.name => {
      outputs = {
        for output_name, flat_name in stack.outputs :
        output_name => try(
          local.custom_stack_template_outputs_by_lower_name[lower(flat_name)].value,
          local.custom_stack_template_outputs_by_lower_name[lower(flat_name)],
          "",
        )
      }
    } if !contains(local.duplicate_custom_stack_names, stack.name)
  }
}

resource "azapi_resource" "custom" {
  count = length(local.custom_stacks) > 0 && data.stack_config.this.custom_stacks_template_url != "" ? 1 : 0

  type      = "Microsoft.Resources/deploymentStacks@2025-07-01"
  name      = "${local.prefix}-custom-stacks"
  parent_id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  location  = local.location

  body = {
    properties = {
      actionOnUnmanage = {
        resources                     = "delete"
        resourceGroups                = "detach"
        managementGroups              = "detach"
        resourcesWithoutDeleteSupport = "fail"
      }
      denySettings = {
        mode               = "denyDelete"
        applyToChildScopes = false
      }
      templateLink = {
        uri = data.stack_config.this.custom_stacks_template_url
      }
      parameters = merge({
        nuonResourceGroupName = { value = azurerm_resource_group.main.name }
        location              = { value = local.location }
        vnetId                = { value = local.network.vnet_id }
        vnetName              = { value = local.network.vnet_name }
        runnerSubnetId        = { value = local.network.runner_subnet_id }
        runnerSubnetName      = { value = local.network.runner_subnet_name }
        publicSubnet1Id       = { value = try(local.network.public_subnet_ids[0], "") }
        publicSubnet1Name     = { value = try(local.network.public_subnet_names[0], "") }
        publicSubnet2Id       = { value = try(local.network.public_subnet_ids[1], "") }
        publicSubnet2Name     = { value = try(local.network.public_subnet_names[1], "") }
        publicSubnet3Id       = { value = try(local.network.public_subnet_ids[2], "") }
        publicSubnet3Name     = { value = try(local.network.public_subnet_names[2], "") }
        privateSubnet1Id      = { value = try(local.network.private_subnet_ids[0], "") }
        privateSubnet1Name    = { value = try(local.network.private_subnet_names[0], "") }
        privateSubnet2Id      = { value = try(local.network.private_subnet_ids[1], "") }
        privateSubnet2Name    = { value = try(local.network.private_subnet_names[1], "") }
        privateSubnet3Id      = { value = try(local.network.private_subnet_ids[2], "") }
        privateSubnet3Name    = { value = try(local.network.private_subnet_names[2], "") }
        publicSubnetIds       = { value = join(",", local.network.public_subnet_ids) }
        publicSubnetNames     = { value = join(",", local.network.public_subnet_names) }
        privateSubnetIds      = { value = join(",", local.network.private_subnet_ids) }
        privateSubnetNames    = { value = join(",", local.network.private_subnet_names) }
      }, local.custom_stack_input_parameters)
    }
  }

  response_export_values = {
    outputs = "properties.outputs"
  }

  delete_query_parameters = {
    "unmanageAction.Resources"                     = ["delete"]
    "unmanageAction.ResourceGroups"                = ["detach"]
    "unmanageAction.ManagementGroups"              = ["detach"]
    "unmanageAction.ResourcesWithoutDeleteSupport" = ["fail"]
  }

  depends_on = [
    module.network,
    azurerm_subscription_template_deployment.network,
    module.runner,
  ]
}
