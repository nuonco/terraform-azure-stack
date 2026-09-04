terraform {
  required_version = ">= 1.9"

  required_providers {
    # Constrained to >= 5.0: the module is developed and tested against 5.x. In
    # 4.x a subnet's service endpoints were a `service_endpoints` list rather
    # than the `service_endpoint` blocks modules/network uses.
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0"
    }
    azapi = {
      source  = "Azure/azapi"
      version = ">= 2.0"
    }
    # >= 0.7.0 adds custom_stacks to stack_config.
    stack = {
      source  = "nuonco/stack"
      version = ">= 0.7.0"
    }
  }
}
