# Build-time variables. Do NOT put real secrets here — pass them at build time
# via `PKR_VAR_*` env vars or an ignored `*.auto.pkrvars.hcl` (see .gitignore).

variable "kube_config" {
  type    = string
  default = "${env("KUBECONFIG")}"
}

variable "namespace" {
  type    = string
  default = "tenant-root"
}

variable "image_name" {
  type        = string
  default     = "workspace-win2022"
  description = "Name of the resulting golden image / VM."
}

# Build-time password for the Administrator account (autounattend) + WinRM. It
# must match the value in autounattend.xml / oobe-unattend.xml. This becomes the
# image's Administrator password, so RESET it at deploy time (do not treat the
# placeholder as safe). It is NOT the autologon secret: configure-autologon.ps1
# does not bake a password and harden.ps1 strips any autologon DefaultPassword.
# Override it: `export PKR_VAR_build_password=...` and edit the two answer files.
variable "build_password" {
  type      = string
  default   = "REPLACE_ME_BUILD_PW"
  sensitive = true
}
