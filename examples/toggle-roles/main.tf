module "azure_stack" {
  source = "../../"

  install_id = var.install_id

  roles = {
    # provision is enabled by default, but can be disabled after installation is complete.
    provision = false

    # break glass roles are disabled by default, but can be enabled to grant elevated access.
    "break-glass" = true
  }
}
