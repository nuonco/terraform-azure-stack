module "azure_stack" {
  source = "../../"

  install_id = var.install_id

  runner_enabled = false
}
