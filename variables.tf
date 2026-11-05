variable "hosts" {
  type        = any
  description = "Hosts to configure: a map of names to addresses, or to host objects with an address and optional host_key, user, port, private_key_file, jump_hosts or os."

  validation {
    condition     = alltrue([for h in var.hosts : contains(["debian", "ubuntu", "rocky", "almalinux", "rhel", "fedora"], try(h.os, "debian"))])
    error_message = "A host object's os must be one of debian, ubuntu, rocky, almalinux, rhel or fedora. CentOS Linux reached end of life on 30 June 2024: use Rocky Linux."
  }
}

variable "ssh_user" {
  type        = string
  default     = "root"
  description = "User to log in as."
}

variable "ssh_port" {
  type        = number
  default     = 22
  description = "SSH port."
}

variable "ssh_private_key_file" {
  type        = string
  default     = null
  description = "Path to a private key. When null, Conn3x uses the SSH agent."
}

variable "ssh_known_hosts_file" {
  type        = string
  default     = null
  description = "known_hosts file to check host keys against. When null, ~/.ssh/known_hosts."
}

variable "ssh_become" {
  type        = bool
  default     = false
  description = "Run commands as root through sudo."
}

variable "java_version" {
  type        = number
  default     = 25
  description = "Java feature release to install, such as 21 or 25. Every supported distribution packages 25; Fedora 45 packages no other LTS release."

  validation {
    condition     = var.java_version >= 8 && floor(var.java_version) == var.java_version
    error_message = "java_version must be a whole Java release number, such as 21 or 25."
  }
}

variable "jdk" {
  type        = bool
  default     = false
  description = "Install the JDK, with javac and the other development tools, instead of the runtime alone."
}

variable "java_source" {
  type        = string
  default     = "distribution"
  description = "Where Java comes from: \"distribution\", the distribution's own OpenJDK packages, or \"temurin\", Eclipse Temurin from Adoptium's repository."

  validation {
    condition     = contains(["distribution", "temurin"], var.java_source)
    error_message = "java_source must be \"distribution\" or \"temurin\"."
  }
}

variable "set_default" {
  type        = bool
  default     = true
  description = "Make this Java the one `java` runs, through the alternatives system, and export its JAVA_HOME to login shells from /etc/profile.d."
}
