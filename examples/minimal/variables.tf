variable "subscription_id" {
  type        = string
  description = "Subscription to configure the azurerm provider with. Must match the subscription Nuon has recorded for this install."
}

variable "install_id" {
  type        = string
  description = "Nuon install ID. Identifies which install to configure; not a credential."
}
