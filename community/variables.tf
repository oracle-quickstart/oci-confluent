# ---------------------------------------------------------------------------------------------------------------------
# Environmental variables
# You probably want to define these as environmental variables.
# Instructions on that are here: https://github.com/cloud-partners/oci-prerequisites
# ---------------------------------------------------------------------------------------------------------------------

# Required by the OCI Provider
variable "tenancy_ocid" {}
variable "compartment_ocid" {}
variable "user_ocid" {}
variable "fingerprint" {}
variable "private_key_path" {}
variable "region" {}

# Key used to SSH to OCI VMs
variable "ssh_public_key" {}
variable "ssh_private_key" {}

# ---------------------------------------------------------------------------------------------------------------------
# Optional variables
# The defaults here will give you a cluster.  You can also modify these.
# ---------------------------------------------------------------------------------------------------------------------

variable "confluent" {
  type = "map"
  default = {
    edition = "Confluent Community"
    version = "5.0.0"
  }
}

variable "bastion" {
  type = "map"
  default = {
    shape = "VM.Standard2.1"
    node_count = 1
  }
}

variable "broker" {
  type = "map"
  default = {
    shape = "VM.Standard2.1"
    node_count = 3
    disk_count = 1
    disk_size = 50
  }
}

variable "zookeeper" {
  type = "map"
  default = {
    shape = "VM.Standard2.1"
    node_count = 3
  }
}

variable "connect" {
  type = "map"
  default = {
    shape = "VM.Standard2.1"
    node_count = 2
  }
}

variable "rest" {
  type = "map"
  default = {
    shape = "VM.Standard2.1"
    node_count = 2
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# Constants
# You probably don't need to change these.
# ---------------------------------------------------------------------------------------------------------------------

// https://docs.cloud.oracle.com/iaas/images/image/cf34ce27-e82d-4c1a-93e6-e55103f90164/
// Oracle-Linux-7.5-2018.08.14-0
variable "images" {
  type = "map"
  default = {
    eu-frankfurt-1 = "ocid1.image.oc1.eu-frankfurt-1.aaaaaaaakzrywmh7kwt7ugj5xqi5r4a7xoxsrxtc7nlsdyhmhqyp7ntobjwq"
    us-ashburn-1 = "ocid1.image.oc1.iad.aaaaaaaa2tq67tvbeavcmioghquci6p3pvqwbneq3vfy7fe7m7geiga4cnxa"
    us-phoenix-1 = "ocid1.image.oc1.phx.aaaaaaaasez4lk2lucxcm52nslj5nhkvbvjtfies4yopwoy4b3vysg5iwjra"
    uk-london-1  = "ocid1.image.oc1.uk-london-1.aaaaaaaalsdgd47nl5tgb55sihdpqmqu2sbvvccjs6tmbkr4nx2pq5gkn63a"
  }
}

variable "vpc-cidr" { default = "10.0.0.0/16" }
variable "ssh_user" { default = "opc" }

#############Stuff from previous template version


## OPTIONAL - Use this to install connectors which are not included as part of confluent platform
variable "ConnectorURLs" {
  default = "http://somehost"
}

variable "ConfluentSecurity" { default = "Disabled" }


##################
#stuff that shouldn't be in env vars

