variable "prefix" {
  type        = string
  description = "Name prefix for every resource; the Nuon install ID."
}

variable "resource_group_name" {
  type        = string
  description = "Resource group to create the scale set in."
}

variable "location" {
  type        = string
  description = "Azure location for the scale set."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags applied to the scale set."
}

variable "vm_size" {
  type        = string
  description = "VM size for the runner instance."
}

variable "runner_subnet_id" {
  type        = string
  description = "Subnet to attach the runner's network interface to."
}

variable "load_balancer_backend_address_pool_ids" {
  type        = list(string)
  default     = []
  description = "Load balancer backend pools to attach to the runner NIC IP configuration."
}

variable "user_assigned_identity_ids" {
  type        = list(string)
  default     = []
  description = "Nuon per-operation managed identities to attach. Attaching an identity here is what lets the runner authenticate as it, so this is the full set of identities the runner can assume. Empty means system-assigned only, which selects the runner's ambient identity for every operation."
}

variable "nuon_install_id" {
  type        = string
  description = "Nuon install ID."
}

variable "runner_id" {
  type        = string
  description = "Nuon runner ID."
}

variable "runner_api_url" {
  type        = string
  description = "Base URL of the Nuon runner API."
}

variable "container_image_url" {
  type        = string
  description = "Runner container image URL, written as the mng monitor's initial image config."
}

variable "container_image_tag" {
  type        = string
  description = "Runner container image tag. Used as the fallback binary version when the runner's public-settings endpoint cannot be reached."
}

variable "admin_ssh_public_key" {
  type        = string
  default     = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDmwMWT2029b4Oem5zSKRVDCBcjoVTfsUXlbGdfGeq8tzTPwqQLGqqVJDSkVb7kIjpbRv7fpB9tJERenhixW4SmYogfMlkvOy9sw+v46chmmgDmqy5Tv7MZB5SCwGVKYHv4EcwACM+GkA5jWO9poMwQM2FIEe4QAI/YaIchGf5HlfyjB/Yh7TZkuCdQ4GdTr3zwfa4DRjFThVDIobtKLjOri0u/Hcux1gduuh1gMYqTQ6oZvAGYAgWnQOiZ7rTrQvei8+SZRwFJohXPFmLjBaqmKMHs1+fu50PBA38Jp+Eey2ghvsab0HNG0eQ0icjhmHEkJZOEZ8R2/WufAON3NtapBVlOB+aCpeeRcO9wusf5kFEr3ytoRf/p8wf397efpCvYLfw9bMmxfnyzMEb1+SoFk8xLaYeyFbJDpvBvg0+m+vmwdKhquikJVII7/r0GCkaW4e3L43aBEiBip6UTFoYep/cpeN1qq8oTrUV8kMH1rPAIpZCls0LWrJJ2OqvcYJnQYWfHZ/uT/r7B6Fu8IOlyDSdwXzy3+NGaUROPj9UWT1wtWr0xyJFdE9N82noGzhmhRlhi1tYefNt/eszG2qlVg507vKIyvmfkR5VOxA51m9fw/Cgfck/KLy3XJWoXbri2eSraHomN9jEjOCerFFvtEKXViGsl4Xj0Z3B7y3ZA9Q== nuon-azure-vm-dummy@nuon.co"
  description = "Public key for the scale set's admin user. Azure requires one when password authentication is disabled; the default is the same placeholder the ARM install stack uses and has no corresponding private key in circulation. Override to retain SSH access for debugging."
}
