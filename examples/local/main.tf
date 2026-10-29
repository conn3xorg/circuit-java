variable "port" {
  type    = number
  default = 2282
}

variable "java_source" {
  type    = string
  default = "distribution"
}

module "java" {
  source = "../.."

  hosts                = { box = "127.0.0.1" }
  ssh_port             = var.port
  ssh_private_key_file = "./id_ed25519"
  ssh_known_hosts_file = "./known_hosts"

  java_version = 25
  jdk          = true
  java_source  = var.java_source
}

output "java_home" {
  value = module.java.java_home
}
