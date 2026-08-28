output "vnet_id" {
  value = azurerm_virtual_network.main.id
}

output "vnet_name" {
  value = azurerm_virtual_network.main.name
}

output "public_subnet_ids" {
  value = azurerm_subnet.public[*].id
}

output "public_subnet_names" {
  value = azurerm_subnet.public[*].name
}

output "private_subnet_ids" {
  value = azurerm_subnet.private[*].id
}

output "private_subnet_names" {
  value = azurerm_subnet.private[*].name
}

# Gated on the NAT association so the runner VM cannot boot before its outbound
# route exists: cloud-init needs egress immediately, and nothing else orders the
# NAT ahead of the scale set.
output "runner_subnet_id" {
  value      = azurerm_subnet.runner.id
  depends_on = [azurerm_subnet_nat_gateway_association.runner]
}

output "runner_subnet_name" {
  value      = azurerm_subnet.runner.name
  depends_on = [azurerm_subnet_nat_gateway_association.runner]
}
