# Disable runner example

Creates networking, identities, the Key Vault and its secrets, but no runner VM
scale set. Useful for cost-parking an install, or for provisioning the stack
ahead of the runner.

```sh
terraform init && terraform apply
```

Note that unlike AWS and GCP, Nuon does not currently read `runner_enabled` back
for Azure installs, so the control plane will not show the runner as
deliberately disabled — it will show it as absent.
