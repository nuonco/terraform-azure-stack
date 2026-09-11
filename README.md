# terraform-azure-stack

Terraform module for provisioning a [Nuon](https://nuon.co) install stack in Azure. It is meant to be applied by a customer against their own Azure subscription. It provisions a dedicated resource group, VNet, Key Vault, and a VM scale set to host the Nuon runner. The runner polls the Nuon control plane for jobs and executes them locally as scoped managed identities.

## Usage

Import the Nuon Stack provider, then provide an install ID.
Provide the required inputs and secrets, and optionally enable or disable roles.

```hcl
provider "azurerm" {
  subscription_id = "00000000-0000-0000-0000-000000000000"

  features {
    key_vault {
      purge_soft_delete_on_destroy = true
    }
  }
}

provider "stack" {}

module "azure_stack" {
  source  = "nuonco/stack/azure"
  version = "~> 1.0"

  install_id = var.install_id

  inputs = {
    vm_size = "Standard_D4s_v3"
  }

  secrets = {
    license_key = { value = var.license_key }
  }

  roles = {
    "break-glass" = true
  }
}
```

The install's location is read from the Nuon control plane; `var.location` overrides it. The subscription comes from the azurerm provider the caller configures, and `checks.tf` warns at plan time if it disagrees with what Nuon recorded.

## Resources

- **Resource group** (`main.tf`) – `<install-id>-rg` by default, which is the name every other Nuon install path uses and what the control plane resolves against. Override with `resource_group_name`. Unlike the ARM install stack, the group is created by this module rather than being a customer prerequisite.
- **Key Vault** (`main.tf`) – RBAC-authorized, standard SKU, named from the first 24 characters of the install ID (Azure's cap). Purge protection is off so a destroyed install's vault name is immediately reusable — which requires callers to set `purge_soft_delete_on_destroy = true` in the provider's `features` block.
- **VNet & subnets** (`modules/network`) – A `10.128.0.0/16` VNet with up to three public subnets, up to three private subnets, and a dedicated runner subnet. Private and runner subnets carry Key Vault and Container Registry service endpoints. Names and CIDRs match the ARM install stack, so a component that resolved a subnet by name there resolves the same one here.
- **NSGs, route table & NAT** (`modules/network`) – A permissive inbound NSG on the public subnets, an empty NSG on the private and runner subnets (Azure's defaults already allow intra-VNet and outbound, and deny inbound), and a single Standard NAT gateway providing egress for every subnet.
- **Runner** (`modules/runner`) – A single-instance Linux VM scale set running Ubuntu 22.04 with a 30 GB disk, no public IP, and the Application Health extension on `:9999/livez` driving automatic instance repair. Set `runner_enabled = false` to skip it.
- **Private telemetry ingress** (`telemetry.tf`) – An internal Standard Load Balancer exposes the runner collector on TCP 4318 by default. Set `enable_telemetry_ingress = false` to opt out.
- **Identities & RBAC** (`iam.tf`) –
  - **Operation identities** – user-assigned managed identities for **provision**, **maintenance**, and **deprovision**, each created only if the app config grants it something. Each gets a subscription-scoped custom role definition built from its `actions` (always including `*/register/action`, so the provider can register resource providers) plus direct assignments of any built-in roles at resource-group scope.
  - **Break-glass identities** – optional, created from the roles the control plane serves and gated on `enabled`.
  - **Custom identities** – optional app-operation roles, same shape and gating as break-glass roles.
  - **Runner system identity** – always holds Key Vault Secrets User on the vault and AcrPull/AcrPush on the resource group, because secret sync and image sync run as the runner's ambient identity. When the app declares no Azure roles at all, it additionally holds Contributor, RBAC Administrator and AKS RBAC Cluster Admin — the pre-per-operation-identity behaviour.
- **Secrets** (`secrets.tf`) – Key Vault secrets for auto-generated values (63-char random) and customer-provided values, plus an empty `telemetry-export-config` secret Nuon populates out of band. Underscores in app-config secret names become hyphens, which Key Vault requires.
- **Custom stacks** (`custom_stacks.tf`) – Applies the control-plane-generated custom ARM template as a subscription-scoped Azure Deployment Stack. Resource-group and subscription-scoped child templates can be mixed, and outputs are reported under `custom_nested_stacks.<name>.outputs`. Managed resources are deleted when Terraform removes the deployment stack.
- **Phone home** (`phone_home.tf`) – A `stack_phone_home` resource that reports provisioning results and the effective install inputs back to Nuon. Its preconditions are where unknown or missing inputs, secrets, and roles fail the plan.

If `custom_stacks` is empty, the Azure Deployment Stack is a no-op and the rest of the install stack is unchanged.

## Private telemetry ingress

Use `module.azure_stack.telemetry_endpoint`, or `{{ .nuon.install_stack.outputs.telemetry_endpoint }}` in Nuon app components, as `OTEL_EXPORTER_OTLP_ENDPOINT` with protocol `http/protobuf`. The private HTTP URL is unauthenticated, stable across runner replacements, and empty when ingress or the runner is disabled. Nuon's install telemetry setting must also be enabled for collection.

Custom networks must allow client traffic on TCP 4318 and probes from `AzureLoadBalancer`; the built-in NSG already allows both. The load balancer uses the actual runner subnet, including for custom VNet templates.

For existing runners, the scale set's `Manual` policy requires upgrading its instances after applying the new backend-pool attachment:

```sh
az vmss update-instances --resource-group <resource-group> --name <vmss-name> --instance-ids '*'
```

The same instance upgrade is needed when detaching the pool before Azure can delete it. New instances use the current model automatically; runner repair remains tied to `:9999/livez`, not collector health.

## How identities differ from AWS and GCP

On AWS an operation role is assumed across an account boundary, gated by a trust policy the module renders. On GCP the runner impersonates a service account via an explicit `serviceAccountTokenCreator` grant. Azure has neither: **attaching a managed identity to the runner's scale set is what grants access to it**, and that is what this module does for every identity it creates.

The consequence is that on Azure every operation identity — break-glass included — is reachable by anything running on the runner. There is no per-operation trust boundary to lean on. This matches the ARM install stack exactly, and it is why `var.roles` matters more here: disabling a role removes its identity entirely, which is the only way to put it out of reach.

Relatedly, when an app declares no Azure roles, the stack creates no operation identities and phone home reports empty client IDs. That is not a misconfiguration — an empty identity ID is how Nuon selects the runner's ambient system identity, which is how every Azure install behaved before per-operation identities existed.

## Region and VM size availability

Two things gate which Azure region an install can be provisioned into, and the second is where provisioning normally fails.

**Resource type availability.** Intersecting the provider location lists for every type the stack creates leaves roughly 47 of Azure's 63 physical regions. NAT gateway is the tightest constraint.

**`Standard_D2s_v3` allocation.** Azure restricts VM SKUs _per subscription per region_, so this layer differs between subscriptions. The failure surfaces at scale-set preflight as a generic `InvalidTemplateDeployment`, with the real reason only in the deployment operations:

```sh
az vm list-skus -l <location> --size Standard_D2s_v3 --all -o json | jq '.[].restrictions'
```

Read the result as:

- no restrictions → the region is usable
- a `Location`-type restriction (`NotAvailableForSubscription`) → the region is blocked
- only `Zone`-type restrictions → **still usable**, because the scale set sets no `zones` and is therefore regional rather than zonal

That last point is why `modules/runner` deliberately sets no `zones`: adding them would silently drop the regions that are only zone-restricted. Set `runner_vm_size` to work around a blocked size.

Quota is a separate axis — a region can pass the SKU check and still fail on it. The runner needs 2 vCPUs:

```sh
az vm list-usage -l <location> -o table | grep -iE 'standardDSv3Family|^cores'
```

## Differences from the ARM install stack

- **Auto-generated secrets are implemented here.** Nothing on the ARM path generates them.
- **The resource group is created by this module**, not a customer prerequisite.
- **No deployment scripts.** Phone home goes through the `stack_phone_home` resource rather than a `deploymentScripts` resource running the Azure CLI, so it carries an Authorization header and the provider owns retries.
- **`runner_enabled` is reported but not yet read.** Nuon does not currently surface a deliberately disabled runner for Azure installs.
- **No `deployment_location`.** That output records where an ARM subscription-scoped deployment record lives, which has no Terraform analogue.

## License

See [LICENSE](./LICENSE).
