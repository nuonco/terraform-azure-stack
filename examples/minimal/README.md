# Minimal example

The simplest working configuration. To provision, give the provider a token.

```sh
export NUON_API_TOKEN=<your-token>
```

Then, apply.

```sh
terraform init && terraform apply
```

The module reads the install's location from the Nuon control plane. Override it
only if you need to provision somewhere else:

```hcl
module "azure_stack" {
  source = "../../"

  install_id = var.install_id
  location   = "westus2"
}
```
