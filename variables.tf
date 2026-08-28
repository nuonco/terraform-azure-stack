##
## Module inputs.
##
## Almost everything this module needs is read from the Nuon control plane via
## the stack_config data source (see stack.tf). Only the values below cannot
## come from the API, or are deliberate caller-side overrides.
##

variable "install_id" {
  type        = string
  description = "Nuon install ID. Identifies which install's configuration to read; not a credential — the stack provider's api_token authorizes the read."

  validation {
    condition     = var.install_id != ""
    error_message = "install_id must be set; it identifies which install's configuration to fetch."
  }
}

##
## Azure target.
##
## The control plane always holds the install's location, so unlike the GCP
## module's project/region these are overrides only. The subscription comes from
## the azurerm provider the caller configures; checks.tf asserts it agrees with
## what Nuon recorded.
##

variable "location" {
  type        = string
  default     = ""
  description = "Azure location to provision the stack in. When empty, read from the Nuon control plane."
}

variable "resource_group_name" {
  type        = string
  default     = ""
  description = "Name of the resource group to create. When empty, defaults to <install-id>-rg, which is the name every other Nuon install path uses and what the control plane expects. Override only when an existing convention requires it."
}

##
## Runner.
##

variable "runner_enabled" {
  type        = bool
  default     = true
  description = "Whether to provision the runner module (VM scale set). Set to false to skip the runner and only create networking, identities, and secrets."
}

variable "runner_vm_size" {
  type        = string
  default     = ""
  description = "Optional override for the runner's VM size. When empty, the size is read from the Nuon app runner config, falling back to Standard_D2s_v3. Azure restricts VM SKUs per subscription per region, so this is the knob to reach for when provisioning fails with SkuNotAvailable."
}

##
## Network.
##

variable "vnet_cidr" {
  type        = string
  default     = "10.128.0.0/16"
  description = "IP range for the install's VNet. Must contain every subnet CIDR below."
}

variable "public_subnet_cidrs" {
  type        = list(string)
  default     = ["10.128.0.0/26", "10.128.0.64/26", "10.128.0.128/26"]
  description = "Public subnet CIDRs, one per zone. One to three entries; the defaults match the ARM install stack."

  validation {
    condition     = length(var.public_subnet_cidrs) >= 1 && length(var.public_subnet_cidrs) <= 3
    error_message = "public_subnet_cidrs must have between 1 and 3 entries."
  }
}

variable "private_subnet_cidrs" {
  type        = list(string)
  default     = ["10.128.130.0/24", "10.128.132.0/24", "10.128.134.0/24"]
  description = "Private subnet CIDRs, one per zone. One to three entries; the defaults match the ARM install stack."

  validation {
    condition     = length(var.private_subnet_cidrs) >= 1 && length(var.private_subnet_cidrs) <= 3
    error_message = "private_subnet_cidrs must have between 1 and 3 entries."
  }
}

variable "runner_subnet_cidr" {
  type        = string
  default     = "10.128.128.0/24"
  description = "CIDR for the dedicated runner subnet."
}

##
## Inputs, secrets, and roles.
##

variable "inputs" {
  type        = map(string)
  default     = {}
  description = "Customer-facing install input values keyed by name. Layered over the values the Nuon control plane holds — any value set here wins — and reported back via phone home, where it becomes the install's current inputs. Keys must match inputs the app declares; unknown keys fail the plan, as does a required input that resolves to no value."
}

variable "secrets" {
  type = map(object({
    description = optional(string)
    required    = optional(bool)
    value       = optional(string)
  }))
  default     = {}
  sensitive   = true
  description = "Secret overrides keyed by name, layered over the stack_config data source. Any field set here wins. Use this to supply secret values the control plane does not hold. A secret the app declares required fails the plan if it resolves to no value, as does a key naming a secret the app does not declare."
}

variable "roles" {
  type        = map(bool)
  default     = {}
  description = "Per-role enable/disable overrides. Break-glass and custom roles are keyed by role name — the full served name or the name without its leading <install-id>- prefix — and a value set here wins over the control plane's enabled flag. The reserved keys provision, maintenance, and deprovision disable an operation role; disabling one prevents Nuon from performing that operation on the install until it is re-enabled and applied. Unknown keys fail the plan."
}
