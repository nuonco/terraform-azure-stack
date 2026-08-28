# The runner VM: a single-instance Linux VM scale set. The root module gates this
# whole module on var.runner_enabled, so there is no count here.
#
# Ported from the ARM install stack's runner.json, including the details that
# look incidental but are not — see the comments on zones and vm_size below.

locals {
  custom_data = templatefile("${path.module}/cloud-init.sh.tftpl", {
    runner_id           = var.runner_id
    runner_api_url      = var.runner_api_url
    container_image_url = var.container_image_url
    container_image_tag = var.container_image_tag
    location            = var.location
  })
}

resource "azurerm_linux_virtual_machine_scale_set" "runner" {
  name                = "${var.prefix}-vmss"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  # Deliberately no `zones`. A zonal scale set fails outright in the regions
  # whose Standard_D2s_v3 restrictions are zone-scoped rather than
  # location-scoped, which is a meaningful share of them — a regional scale set
  # provisions in those regions fine. Adding zones here would silently narrow
  # the set of regions an install can target.
  sku       = var.vm_size
  instances = 1

  # The runner reads its configuration from custom_data at first boot, so an
  # in-place upgrade would not apply a change. Manual mode plus the replace
  # repair action below means instances are recreated rather than reconfigured.
  upgrade_mode         = "Manual"
  overprovision        = false
  computer_name_prefix = var.prefix
  admin_username       = "nuon"
  custom_data          = base64encode(local.custom_data)

  disable_password_authentication = true

  admin_ssh_key {
    username   = "nuon"
    public_key = var.admin_ssh_public_key
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  os_disk {
    storage_account_type = "Standard_LRS"
    caching              = "ReadWrite"
    disk_size_gb         = 30
  }

  network_interface {
    name    = "${var.prefix}-nic"
    primary = true

    ip_configuration {
      name      = "${var.prefix}-ipc"
      primary   = true
      subnet_id = var.runner_subnet_id
    }
  }

  # The runner authenticates to Nuon as its own managed identity, and to Azure
  # via ARM_USE_MSI. Attaching the per-operation identities is what lets it
  # assume them; with none attached, every operation runs as the system
  # identity, which is how Azure installs behaved before per-operation
  # identities existed.
  identity {
    type         = length(var.user_assigned_identity_ids) > 0 ? "SystemAssigned, UserAssigned" : "SystemAssigned"
    identity_ids = var.user_assigned_identity_ids
  }

  # Reports the runner's own health on :9999/livez, which is what makes
  # automatic_instance_repair able to tell a wedged runner from a booting one.
  extension {
    name                       = "ApplicationHealth"
    publisher                  = "Microsoft.ManagedServices"
    type                       = "ApplicationHealthLinux"
    type_handler_version       = "1.0"
    auto_upgrade_minor_version = true

    settings = jsonencode({
      protocol       = "http"
      port           = 9999
      requestPath    = "/livez"
      numberOfProbes = 3
    })
  }

  automatic_instance_repair {
    enabled = true
    # Long enough for docker install plus the runner binary download; a shorter
    # grace period would replace instances mid-bootstrap in a loop.
    grace_period = "PT10M"
    action       = "Replace"
  }
}
