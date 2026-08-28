# Toggle roles example

Turning individual operation, break-glass and custom roles on and off.

On Azure a role's identity is reachable by anything running on the runner,
because attaching a managed identity to the runner's scale set is what grants
access to it. There is no per-operation trust boundary as there is on AWS, so
`roles` is the control for narrowing what the runner can do — disabling a role
here removes the identity entirely.

```sh
terraform init && terraform apply
```

Disabling `provision` prevents Nuon from provisioning the install until it is
re-enabled and re-applied.
