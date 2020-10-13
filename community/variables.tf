# ---------------------------------------------------------------------------------------------------------------------
# Environmental variables
# You probably want to define these as environmental variables.
# Instructions on that are here: https://github.com/cloud-partners/oci-prerequisites
# ---------------------------------------------------------------------------------------------------------------------

# Required by the OCI Provider
variable "tenancy_ocid" {
}

variable "compartment_ocid" {
}

variable "user_ocid" {
}

variable "fingerprint" {
}

variable "private_key_path" {
}

variable "region" {
}

# Key used to SSH to OCI VMs
variable "ssh_public_key" {
}

variable "ssh_private_key" {
}

# ---------------------------------------------------------------------------------------------------------------------
# Optional variables
# The defaults here will give you a cluster.  You can also modify these.
# ---------------------------------------------------------------------------------------------------------------------

variable "confluent" {
  type = map(string)
  default = {
    edition = "Community"
    version = "6.0.0"
  }
}

variable "broker" {
  type = map(string)
  default = {
    shape      = "VM.Standard2.4"
    node_count = 3
    disk_count = 1
    disk_size  = 50
  }
}

variable "zookeeper" {
  type = map(string)
  default = {
    shape      = "VM.Standard2.2"
    node_count = 3
  }
}

variable "connect" {
  type = map(string)
  default = {
    shape      = "VM.Standard2.2"
    node_count = 2
  }
}

variable "rest" {
  type = map(string)
  default = {
    shape      = "VM.Standard2.2"
    node_count = 2
  }
}

variable "schema_registry" {
  type = map(string)
  default = {
    shape      = "VM.Standard2.2"
    node_count = 1
  }
}

variable "ksql" {
  type = map(string)
  default = {
    shape      = "VM.Standard2.1"
    node_count = 2
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# Constants
# You probably don't need to change these.
# ---------------------------------------------------------------------------------------------------------------------

// https://docs.cloud.oracle.com/iaas/images/image/66379f54-edd0-4294-895f-47291a3eb4ed/
// Oracle-Linux-7.6-2019.02.20-0
variable "images" {
  type = map(string)
  default = {
    ca-toronto-1   = "ocid1.image.oc1.ca-toronto-1.aaaaaaaa7ac57wwwhputaufcbf633ojir6scqa4yv6iaqtn3u64wisqd3jjq"
    eu-frankfurt-1 = "ocid1.image.oc1.eu-frankfurt-1.aaaaaaaa527xpybx2azyhcz2oyk6f4lsvokyujajo73zuxnnhcnp7p24pgva"
    uk-london-1    = "ocid1.image.oc1.uk-london-1.aaaaaaaarruepdlahln5fah4lvm7tsf4was3wdx75vfs6vljdke65imbqnhq"
    us-ashburn-1   = "ocid1.image.oc1.iad.aaaaaaaannaquxy7rrbrbngpaqp427mv426rlalgihxwdjrz3fr2iiaxah5a"
    us-phoenix-1   = "ocid1.image.oc1.phx.aaaaaaaacss7qgb6vhojblgcklnmcbchhei6wgqisqmdciu3l4spmroipghq"
  }
}

variable "vpc-cidr" {
  default = "10.0.0.0/16"
}
