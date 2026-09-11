locals {
  telemetry_ingress_enabled = var.runner_enabled && var.enable_telemetry_ingress
  telemetry_endpoint        = local.telemetry_ingress_enabled ? "http://${azurerm_lb.telemetry[0].private_ip_address}:4318" : ""
}

# A private Standard Load Balancer gives workloads in the VNet a stable OTLP
# endpoint without changing the runner subnet's NAT-backed outbound path.
resource "azurerm_lb" "telemetry" {
  count = local.telemetry_ingress_enabled ? 1 : 0

  name                = "${local.prefix}-telemetry-lb"
  resource_group_name = azurerm_resource_group.main.name
  location            = local.location
  tags                = local.tags
  sku                 = "Standard"

  frontend_ip_configuration {
    name                          = "telemetry"
    subnet_id                     = local.network.runner_subnet_id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_lb_backend_address_pool" "telemetry" {
  count = local.telemetry_ingress_enabled ? 1 : 0

  name            = "telemetry"
  loadbalancer_id = azurerm_lb.telemetry[0].id
}

# This probe controls only load-balancer routing. Runner repair remains driven
# exclusively by the ApplicationHealth extension on :9999/livez.
resource "azurerm_lb_probe" "telemetry" {
  count = local.telemetry_ingress_enabled ? 1 : 0

  name            = "otlp-http"
  loadbalancer_id = azurerm_lb.telemetry[0].id
  protocol        = "Tcp"
  port            = 4318
}

resource "azurerm_lb_rule" "telemetry" {
  count = local.telemetry_ingress_enabled ? 1 : 0

  name                           = "otlp-http"
  loadbalancer_id                = azurerm_lb.telemetry[0].id
  protocol                       = "Tcp"
  frontend_port                  = 4318
  backend_port                   = 4318
  frontend_ip_configuration_name = "telemetry"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.telemetry[0].id]
  probe_id                       = azurerm_lb_probe.telemetry[0].id
  disable_outbound_snat          = true
}
