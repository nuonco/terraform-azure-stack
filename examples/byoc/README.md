# BYOC example

Applying the install stack into a customer's own Azure subscription — the normal
production shape. The customer runs this, so the azurerm provider is configured
with their subscription and their credentials, and the module reads everything
else from Nuon.

```sh
export NUON_API_TOKEN=<your-token>
export ARM_SUBSCRIPTION_ID=<customer-subscription-id>

terraform init && terraform apply
```

Install inputs and secrets can be supplied here when the control plane does not
hold them:

```hcl
module "azure_stack" {
  source = "../../"

  install_id = var.install_id

  inputs = {
    domain = "customer.example.com"
  }

  secrets = {
    license_key = { value = var.license_key }
  }
}
```
