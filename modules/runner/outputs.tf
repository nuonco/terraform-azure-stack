output "vmss_name" {
  value = azurerm_linux_virtual_machine_scale_set.runner.name
}

output "vmss_id" {
  value = azurerm_linux_virtual_machine_scale_set.runner.id
}

# Principal ID of the scale set's system-assigned identity. Secret sync and
# image sync run as this identity rather than a per-operation one, so the
# control plane needs it to grant cluster access.
output "vmss_principal_id" {
  value = azurerm_linux_virtual_machine_scale_set.runner.identity[0].principal_id
}
