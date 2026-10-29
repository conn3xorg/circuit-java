# Facts give each host's distribution, which picks the package names and
# Adoptium's repository, its release, which picks the apt suite, and its
# architecture, which Debian and Ubuntu put in Java's directory name.
data "conn3x_host" "facts" {
  for_each = var.hosts

  ssh {
    host             = try(each.value.address, each.value)
    host_key         = try(each.value.host_key, null)
    user             = try(each.value.user, var.ssh_user)
    port             = try(each.value.port, var.ssh_port)
    private_key_file = try(each.value.private_key_file, var.ssh_private_key_file)
    jump_hosts       = try(each.value.jump_hosts, null)
    known_hosts_file = var.ssh_known_hosts_file
  }

  lifecycle {
    postcondition {
      condition     = try(each.value.os, self.os_id) == self.os_id
      error_message = "Host ${each.key} is ${self.os_id}, not the ${try(each.value.os, "")} its os says."
    }

    postcondition {
      condition     = var.java_source != "temurin" || self.os_family != "debian" || contains(keys(local.temurin_suites), self.os_version)
      error_message = "Adoptium has no apt suite this circuit knows for ${self.os_id} ${self.os_version} on host ${each.key}. Use java_source = \"distribution\"."
    }
  }
}

locals {
  # A host object's os stands in for the facts of a host created in the
  # same plan, which can't be read until it exists.
  os     = { for name, h in var.hosts : name => try(h.os, data.conn3x_host.facts[name].os_id) }
  family = { for name, o in local.os : name => contains(["debian", "ubuntu"], o) ? "debian" : "redhat" }

  v           = var.java_version
  kind        = var.jdk ? "jdk" : "jre"
  debian_arch = { x86_64 = "amd64", aarch64 = "arm64", ppc64le = "ppc64el" }
  arch        = { for name in keys(var.hosts) : name => lookup(local.debian_arch, data.conn3x_host.facts[name].arch, data.conn3x_host.facts[name].arch) }

  # Adoptium publishes one apt suite per release codename, and os-release
  # on Debian and Ubuntu gives only the number.
  temurin_suites = {
    "12"    = "bookworm"
    "13"    = "trixie"
    "22.04" = "jammy"
    "24.04" = "noble"
    "26.04" = "resolute"
  }

  # Red Hat's runtime package is headless already; its JDK is -devel.
  # Adoptium ships no headless runtime for apt, so temurin-N-jre there
  # brings a few X11 libraries along.
  package = {
    distribution = {
      debian = "openjdk-${local.v}-${local.kind}-headless"
      redhat = var.jdk ? "java-${local.v}-openjdk-devel" : "java-${local.v}-openjdk-headless"
    }
    temurin = {
      debian = "temurin-${local.v}-${local.kind}"
      redhat = var.jdk ? "temurin-${local.v}-jdk" : "temurin-${local.v}-jre-headless"
    }
  }

  # On the Red Hat family, jre-N and java-N are links the alternatives
  # system keeps pointing at the newest build, so they survive an update.
  # Temurin's rpms keep a link named after the package for the same reason.
  java_home = { for name, f in local.family : name => (
    var.java_source == "temurin" ? (f == "debian" ? "/usr/lib/jvm/temurin-${local.v}-${local.kind}-${local.arch[name]}" : "/usr/lib/jvm/${local.package.temurin.redhat}") :
    f == "debian" ? "/usr/lib/jvm/java-${local.v}-openjdk-${local.arch[name]}" :
    var.jdk ? "/usr/lib/jvm/java-${local.v}" : "/usr/lib/jvm/jre-${local.v}"
  ) }

  # The alternatives system wants the real path it registered, not a link
  # to it.
  tools = var.jdk ? ["java", "javac"] : ["java"]
  alternatives = { for name, home in local.java_home : name => {
    set   = join(" && ", [for t in local.tools : "update-alternatives --set ${t} \"$(readlink -f ${home}/bin/${t})\""])
    check = join(" && ", [for t in local.tools : "[ \"$(readlink -f /usr/bin/${t})\" = \"$(readlink -f ${home}/bin/${t})\" ]"])
  } }
}

circuit "temurin" {
  hosts = var.java_source == "temurin" ? var.hosts : {}

  ssh {
    user             = var.ssh_user
    port             = var.ssh_port
    private_key_file = var.ssh_private_key_file
    known_hosts_file = var.ssh_known_hosts_file
    become           = var.ssh_become
  }

  # Adoptium builds one rpm repository for Fedora and one for RHEL, which
  # Rocky Linux, AlmaLinux and CentOS Stream use too. Its signing key has
  # no expiry date.
  step "repo" {
    repository {
      name   = "adoptium"
      url    = local.family[each.key] == "debian" ? "https://packages.adoptium.net/artifactory/deb" : "https://packages.adoptium.net/artifactory/rpm/${local.os[each.key] == "fedora" ? "fedora" : "rhel"}/$releasever/$basearch"
      key    = file("${path.module}/files/adoptium.asc")
      suites = local.family[each.key] == "debian" ? [local.temurin_suites[data.conn3x_host.facts[each.key].os_version]] : null
    }
  }
}

circuit "java" {
  hosts = var.hosts

  ssh {
    user             = var.ssh_user
    port             = var.ssh_port
    private_key_file = var.ssh_private_key_file
    known_hosts_file = var.ssh_known_hosts_file
    become           = var.ssh_become
  }

  step "package" {
    depends_on = [conn3x_repository.temurin__repo]
    package {
      name = local.package[var.java_source][local.family[each.key]]
    }
  }
}

circuit "default" {
  hosts = var.set_default ? var.hosts : {}

  ssh {
    user             = var.ssh_user
    port             = var.ssh_port
    private_key_file = var.ssh_private_key_file
    known_hosts_file = var.ssh_known_hosts_file
    become           = var.ssh_become
  }

  # A package update can move the links, so the check runs again after
  # one.
  step "alternatives" {
    command {
      command  = local.alternatives[each.key].set
      unless   = local.alternatives[each.key].check
      triggers = { package = conn3x_package.java__package[each.key].revision }
    }
  }

  step "profile" {
    file {
      path    = "/etc/profile.d/java_home.sh"
      content = "# Written by Conn3x. Changes here are overwritten on the next apply.\nexport JAVA_HOME=${local.java_home[each.key]}\n"
      mode    = "0644"
    }
  }
}
