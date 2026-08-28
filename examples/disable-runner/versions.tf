terraform {
  required_version = ">= 1.9"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 5.0"
    }
    stack = {
      source  = "nuonco/stack"
      version = ">= 0.6.0"
    }
  }
}

provider "azurerm" {
  subscription_id = var.subscription_id

  features {
    key_vault {
      # The module leaves purge protection off so a destroyed install's vault
      # name can be reused; purging on destroy is what makes that effective.
      purge_soft_delete_on_destroy = true
    }
  }
}

provider "stack" {}
