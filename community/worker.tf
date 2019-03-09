resource "oci_core_instance" "WorkerNode" {
  count = "${var.WorkerNodeCount}"
  availability_domain = "${lookup(data.oci_identity_availability_domains.ADs.availability_domains[var.AD - 1],"name")}"
  compartment_id      = "${var.compartment_ocid}"
  display_name        = "CF Worker ${format("%01d", count.index+1)}"
  hostname_label      = "CF-Worker-${format("%01d", count.index+1)}"
  shape               = "${var.WorkerInstanceShape}"
  subnet_id	      = "${oci_core_subnet.public.*.id[var.AD - 1]}"

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

# Get list of VNICS for Worker Nodes
data "oci_core_vnic_attachments" "worker_node_vnics" {
  compartment_id      = "${var.compartment_ocid}"
  availability_domain = "${lookup(data.oci_identity_availability_domains.ADs.availability_domains[var.AD - 1],"name")}"
  instance_id = "${oci_core_instance.WorkerNode.0.id}"
}

data "oci_core_vnic" "worker_node_vnic" {
  vnic_id = "${lookup(data.oci_core_vnic_attachments.worker_node_vnics.vnic_attachments[0],"vnic_id")}"
}

output "3 - Control Center Web URL  " {
value = <<END
        http://${data.oci_core_vnic.worker_node_vnic.public_ip_address}:9021/
END
}
