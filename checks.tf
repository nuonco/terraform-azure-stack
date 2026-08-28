# This module intentionally declares no `provider "azurerm"` or `provider
# "stack"` block so that callers can compose it with count/for_each and pass in
# aliased providers. The tradeoff is that the azurerm provider's subscription is
# set by the caller, independently of the target the Nuon control plane believes
# this install belongs to.
#
# A mismatch is quiet but damaging — resources would be created in one
# subscription or location while the outputs, the phone-home payload, and the
# Key Vault URIs all reference another. This surfaces it at plan time, validated
# against the control plane rather than against another caller-supplied value.
#
# A `check` block warns without failing the apply, which is deliberate: an
# operator overriding the target on purpose should not be hard-blocked. The hard
# failure — no location resolving at all — is a precondition on
# stack_phone_home.this instead.

check "azure_subscription_matches_stack_config" {
  assert {
    # Skipped when the control plane has nothing recorded: there is no
    # disagreement to report, only an absence.
    condition = (
      data.stack_config.this.azure.subscription_id == "" ||
      data.azurerm_client_config.current.subscription_id == data.stack_config.this.azure.subscription_id
    )
    error_message = "The azurerm provider is configured for subscription ${data.azurerm_client_config.current.subscription_id}, but the Nuon control plane reports this install's subscription as ${data.stack_config.this.azure.subscription_id}. Point the azurerm provider at ${data.stack_config.this.azure.subscription_id}."
  }
}

check "azure_tenant_matches_stack_config" {
  assert {
    condition = (
      data.stack_config.this.azure.subscription_tenant_id == "" ||
      data.azurerm_client_config.current.tenant_id == data.stack_config.this.azure.subscription_tenant_id
    )
    error_message = "The azurerm provider is authenticated against tenant ${data.azurerm_client_config.current.tenant_id}, but the Nuon control plane reports this install's tenant as ${data.stack_config.this.azure.subscription_tenant_id}."
  }
}

check "azure_location_matches_stack_config" {
  assert {
    condition     = var.location == "" || data.stack_config.this.azure.location == "" || var.location == data.stack_config.this.azure.location
    error_message = "var.location is ${var.location}, but the Nuon control plane reports this install's location as ${data.stack_config.this.azure.location}. The install's sandbox and components already assume the control plane's value."
  }
}

# Standard_D2s_v3 — the default runner size — is restricted per subscription per
# region, and that is where Azure provisioning normally fails. There is no check
# for it here on purpose: azurerm 5.x removed the data source that listed
# available sizes, and the SKU restrictions API is not exposed by the provider at
# all, so any check would be guesswork.
#
# When an apply fails at VMSS preflight with a generic
# InvalidTemplateDeployment, the real reason is in the deployment operations:
#
#   az vm list-skus -l <location> --size Standard_D2s_v3 --all \
#     -o json | jq '.[].restrictions'
#
# A Location-type restriction (NotAvailableForSubscription) blocks the region; a
# Zone-type restriction does not, because the scale set sets no `zones` and is
# therefore regional. Set var.runner_vm_size to work around a blocked size.
