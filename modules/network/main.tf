# The install's VNet. Subnet names, CIDRs and the NSG/NAT wiring mirror the ARM
# install stack's vnet.json so a component that resolved a subnet by name under
# the ARM path resolves the same one here.
#
# Subnets are declared as azurerm_subnet resources rather than inline blocks on
# the VNet: inline blocks are authoritative, so anything Azure or a vendor's own
# tooling adds to the VNet later would be reverted on the next apply.

resource "azurerm_public_ip" "nat" {
  name                = "${var.prefix}-natgw-pip"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  # Standard SKU + Static is required by NAT gateway; Basic is not accepted.
  sku               = "Standard"
  allocation_method = "Static"
}

resource "azurerm_nat_gateway" "main" {
  name                    = "${var.prefix}-natgw"
  resource_group_name     = var.resource_group_name
  location                = var.location
  tags                    = var.tags
  sku_name                = "Standard"
  idle_timeout_in_minutes = 4
}

resource "azurerm_nat_gateway_public_ip_association" "main" {
  nat_gateway_id       = azurerm_nat_gateway.main.id
  public_ip_address_id = azurerm_public_ip.nat.id
}

# Permissive inbound, matching the ARM template's public NSG. Public subnets
# host vendor-managed ingress, so the stack does not constrain them; the private
# and runner subnets get the empty NSG below instead.
resource "azurerm_network_security_group" "public" {
  name                = "${var.prefix}-public-nsg"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  security_rule {
    name                       = "Allow-All-Inbound"
    description                = "Allow all inbound traffic from any source"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
    access                     = "Allow"
    priority                   = 200
    direction                  = "Inbound"
  }
}

# No rules: Azure's default rules already permit intra-VNet traffic and all
# outbound, and deny inbound from the internet.
resource "azurerm_network_security_group" "private" {
  name                = "${var.prefix}-private-nsg"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

resource "azurerm_route_table" "private" {
  name                          = "${var.prefix}-private-routetable"
  resource_group_name           = var.resource_group_name
  location                      = var.location
  tags                          = var.tags
  bgp_route_propagation_enabled = true
}

resource "azurerm_virtual_network" "main" {
  name                = "${var.prefix}-vnet"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
  address_space       = [var.vnet_cidr]
}

resource "azurerm_subnet" "public" {
  count                = length(var.public_subnet_cidrs)
  name                 = "${var.prefix}-public-subnet-zone${count.index + 1}"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.public_subnet_cidrs[count.index]]

  private_endpoint_network_policies             = "Disabled"
  private_link_service_network_policies_enabled = true
}

resource "azurerm_subnet" "runner" {
  name                 = "${var.prefix}-private-runner-subnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.runner_subnet_cidr]

  private_endpoint_network_policies             = "Disabled"
  private_link_service_network_policies_enabled = true

  # The runner reads secrets from Key Vault and pulls images from ACR over the
  # VNet rather than the public endpoints.
  service_endpoint {
    service = "Microsoft.KeyVault"
  }

  service_endpoint {
    service = "Microsoft.ContainerRegistry"
  }
}

resource "azurerm_subnet" "private" {
  count                = length(var.private_subnet_cidrs)
  name                 = "${var.prefix}-private-subnet-zone${count.index + 1}"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.private_subnet_cidrs[count.index]]

  private_endpoint_network_policies             = "Disabled"
  private_link_service_network_policies_enabled = true

  service_endpoint {
    service = "Microsoft.KeyVault"
  }

  service_endpoint {
    service = "Microsoft.ContainerRegistry"
  }
}

##
## NSG and NAT gateway associations.
##
## Every subnet routes egress through the single NAT gateway, matching the ARM
## template: "public" and "private" are naming conventions downstream components
## consume, not a difference in egress path.
##

resource "azurerm_subnet_network_security_group_association" "public" {
  count                     = length(var.public_subnet_cidrs)
  subnet_id                 = azurerm_subnet.public[count.index].id
  network_security_group_id = azurerm_network_security_group.public.id
}

resource "azurerm_subnet_network_security_group_association" "private" {
  count                     = length(var.private_subnet_cidrs)
  subnet_id                 = azurerm_subnet.private[count.index].id
  network_security_group_id = azurerm_network_security_group.private.id
}

resource "azurerm_subnet_network_security_group_association" "runner" {
  subnet_id                 = azurerm_subnet.runner.id
  network_security_group_id = azurerm_network_security_group.private.id
}

resource "azurerm_subnet_nat_gateway_association" "public" {
  count          = length(var.public_subnet_cidrs)
  subnet_id      = azurerm_subnet.public[count.index].id
  nat_gateway_id = azurerm_nat_gateway.main.id
}

resource "azurerm_subnet_nat_gateway_association" "private" {
  count          = length(var.private_subnet_cidrs)
  subnet_id      = azurerm_subnet.private[count.index].id
  nat_gateway_id = azurerm_nat_gateway.main.id
}

resource "azurerm_subnet_nat_gateway_association" "runner" {
  subnet_id      = azurerm_subnet.runner.id
  nat_gateway_id = azurerm_nat_gateway.main.id
}
