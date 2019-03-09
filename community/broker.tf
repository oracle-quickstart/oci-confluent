resource "oci_core_instance" "BrokerNode" {
  count		      = "${var.BrokerNodeCount}"
  availability_domain = "${lookup(data.oci_identity_availability_domains.ADs.availability_domains[var.AD - 1],"name")}"
  compartment_id      = "${var.compartment_ocid}"
  display_name        = "CF Broker ${format("%01d", count.index+1)}"
  hostname_label      = "CF-Broker-${format("%01d", count.index+1)}"
  shape               = "${var.BrokerInstanceShape}"
  subnet_id           = "${oci_core_subnet.public.*.id[var.AD - 1]}"

  source_details {
    source_type = "image"
    source_id = "${var.InstanceImageOCID[var.region]}"
  }

  metadata {
    ssh_authorized_keys = "${var.ssh_public_key}"
    user_data = "${base64encode(data.template_file.boot_script.rendered)}"
  }

  timeouts {
    create = "30m"
  }
}

data "oci_core_vnic_attachments" "broker_node_vnics" {
  compartment_id      = "${var.compartment_ocid}"
  availability_domain = "${lookup(data.oci_identity_availability_domains.ADs.availability_domains[var.AD - 1],"name")}"
  instance_id = "${oci_core_instance.BrokerNode.0.id}"
}

data "oci_core_vnic" "broker_node_vnic" {
  vnic_id = "${lookup(data.oci_core_vnic_attachments.broker_node_vnics.vnic_attachments[0],"vnic_id")}"
}

resource "oci_core_volume" "BrokerVolume1" {
  count="${var.BrokerNodeCount}"
  availability_domain = "${lookup(data.oci_identity_availability_domains.ADs.availability_domains[var.AD - 1],"name")}"
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
