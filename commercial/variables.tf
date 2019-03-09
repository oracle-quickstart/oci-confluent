###
## Variables here are sourced from env, but still need to be initialized for Terraform
###

variable "tenancy_ocid" {}
variable "user_ocid" {}
variable "fingerprint" {}
variable "private_key_path" {}
variable "region" { default = "us-phoenix-1" }

variable "compartment_ocid" {}
variable "ssh_public_key" {}
variable "ssh_private_key" {}


variable "ssh_private_key_path" {}


## An AD to deploy the Confluent platform. Valid values: 1,2,3 for regions with 3 ADs
variable "AD" { default = "2" }

variable "InstanceImageOCID" {
    type = "map"
    default = {
        // See https://docs.us-phoenix-1.oraclecloud.com/images/ or https://docs.cloud.oracle.com/iaas/images/
        // Oracle-provided image "CentOS-7-2018.08.15-0"
	eu-frankfurt-1 = "ocid1.image.oc1.eu-frankfurt-1.aaaaaaaatz6zixwltzswnmzi2qxdjcab6nw47xne4tco34kn6hltzdppmada" 
	us-ashburn-1 = "ocid1.image.oc1.iad.aaaaaaaah6ui3hcaq7d43esyrfmyqb3mwuzn4uoxjlbbdwoiicdmntlvwpda"
	uk-london-1 = "ocid1.image.oc1.uk-london-1.aaaaaaaai3czrt22cbu5uytpci55rcy4mpi4j7wm46iy5wdieqkestxve4yq"
	us-phoenix-1 = "ocid1.image.oc1.phx.aaaaaaaarbacra7juwrie5idcadtgbj3llxcu7p26rj4t3xujyqwwopy2wva"
    }
}

variable "BrokerNodeCount" { default = "3" } 

## Number of independent Zookeepers (if 0, zookeeper will be deployed on the Kafka brokers). Valid values: 0,1,3,5
variable "ZookeeperNodeCount" { default = "0" }

variable "WorkerNodeCount" { default = "2" } 


variable "BrokerInstanceShape" {
  default = "VM.Standard1.2"
}

variable "ZookeeperInstanceShape" {
  default = "VM.Standard1.1"
}

variable "WorkerInstanceShape" {
  default = "VM.Standard1.2"
}


## Block Storage in GiB for Broker Node
variable "BrokerNodeStorage" {
  default = "512"
}



## Confluent Cluster Info
variable "ClusterName" {
  default = "ocicf"
}

variable "ConfluentEdition" {
  default = "Confluent Enterprise"
}

variable "ConfluentVersion" {
  default = "5.0.0"
}

## OPTIONAL - Use this to install connectors which are not included as part of confluent platform 
variable "ConnectorURLs" {
  default = "http://somehost"
}

variable "ConfluentSecurity" { default = "Disabled" }


