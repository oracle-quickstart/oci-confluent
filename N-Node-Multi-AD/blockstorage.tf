###
### Block Volumes for Broker Nodes - used to store Kafka data
###

resource "oci_core_volume" "BrokerVolume1" {
  count="${var.BrokerNodeCount}"
  availability_domain = "${lookup(data.oci_identity_availability_domains.ADs.availability_domains[count.index%3],"name")}"
  compartment_id = "${var.compartment_ocid}"
  display_name = "CF Broker ${format("%01d", count.index+1)} Volume 1"
  size_in_gbs = "${var.BrokerNodeStorage}"
}

resource "oci_core_volume_attachment" "BrokerAttachment1" {
  count="${var.BrokerNodeCount}"
  attachment_type = "iscsi"
  compartment_id = "${var.compartment_ocid}"
  instance_id = "${oci_core_instance.BrokerNode.*.id[count.index]}"
  volume_id = "${oci_core_volume.BrokerVolume1.*.id[count.index]}"
}

