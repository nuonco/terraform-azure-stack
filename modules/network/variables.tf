variable "prefix" {
  type        = string
  description = "Name prefix for every resource; the Nuon install ID."
}

variable "resource_group_name" {
  type        = string
  description = "Resource group to create the network in."
}

variable "location" {
  type        = string
  description = "Azure location for every resource."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags applied to every resource."
}

variable "vnet_cidr" {
  type        = string
  description = "Address space for the VNet."
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "Public subnet CIDRs, one per zone."
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "Private subnet CIDRs, one per zone."
}

variable "runner_subnet_cidr" {
  type        = string
  description = "CIDR for the dedicated runner subnet."
}
