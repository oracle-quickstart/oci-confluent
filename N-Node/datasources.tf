# Gets a list of Availability Domains
data "oci_identity_availability_domains" "ADs" {
  compartment_id = "${var.tenancy_ocid}"
}

data "template_file" "boot_script" {
  template =  "${file("../scripts/boot.sh.tpl")}"
  vars {
    ClusterName = "${var.ClusterName}"
    ConfluentEdition = "${var.ConfluentEdition}"
    ConfluentVersion = "${var.ConfluentVersion}"
    ConnectorURLs = "${var.ConnectorURLs}"
    ConfluentSecurity = "${var.ConfluentSecurity}"
    BrokerNodeCount = "${var.BrokerNodeCount}"
    ZookeeperNodeCount = "${var.ZookeeperNodeCount}"
    WorkerNodeCount = "${var.WorkerNodeCount}"
    VPCCIDR = "${var.VPC-CIDR}"
  }
}


# Get list of VNICS for Broker Nodes
data "oci_core_vnic_attachments" "broker_node_vnics" {
  compartment_id      = "${var.compartment_ocid}"
  availability_domain = "${lookup(data.oci_identity_availability_domains.ADs.availability_domains[var.AD - 1],"name")}"
  instance_id = "${oci_core_instance.BrokerNode.0.id}"
}

data "oci_core_vnic" "broker_node_vnic" {
  vnic_id = "${lookup(data.oci_core_vnic_attachments.broker_node_vnics.vnic_attachments[0],"vnic_id")}"
}

# Get list of VNICS for Worker Nodes
data "oci_core_vnic_attachments" "worker_node_vnics" {
  compartment_id      = "${var.compartment_ocid}"
  availability_domain = "${lookup(data.oci_identity_availability_domains.ADs.availability_domains[var.AD - 1],"name")}"
  instance_id = "${oci_core_instance.WorkerNode.0.id}"
}

data "oci_core_vnic" "worker_node_vnic" {
  vnic_id = "${lookup(data.oci_core_vnic_attachments.worker_node_vnics.vnic_attachments[0],"vnic_id")}"
}
 
