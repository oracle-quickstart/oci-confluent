resource "oci_core_instance" "broker" {
  display_name        = "broker-${count.index}"
  compartment_id      = "${var.compartment_ocid}"
  availability_domain = "${lookup(data.oci_identity_availability_domains.availability_domains.availability_domains[0],"name")}"
  shape               = "${var.broker["shape"]}"
  subnet_id           = "${oci_core_subnet.private_subnet.id}"

  source_details {
    source_id   = "${var.images[var.region]}"
    source_type = "image"
  }

  create_vnic_details {
    subnet_id      = "${oci_core_subnet.private_subnet.id}"
    hostname_label = "broker-${count.index}"
    assign_public_ip = "false"
  }

  fault_domain = "${lookup(data.oci_identity_fault_domains.fault_domains.fault_domains[count.index%3],"name")}" 

  metadata {
    ssh_authorized_keys = "${var.ssh_public_key}"

    user_data = "${base64encode(join("\n", list(
      "#!/usr/bin/env bash",
      file("../scripts/broker.sh")
    )))}"
  }

  count = "${var.broker["node_count"]}"
}


resource "oci_core_volume" "broker" {
  count               = "${var.broker["node_count"] * var.broker["disk_count"]}"
  availability_domain = "${lookup(data.oci_identity_availability_domains.availability_domains.availability_domains[0],"name")}"
  compartment_id      = "${var.compartment_ocid}"
  display_name        = "broker${count.index % var.broker["node_count"]}-volume${floor(count.index / var.broker["node_count"])}"
  size_in_gbs         = "${var.broker["disk_size"]}"
}

resource "oci_core_volume_attachment" "broker" {
  count           = "${var.broker["node_count"] * var.broker["disk_count"]}"
  attachment_type = "iscsi"
  compartment_id  = "${var.compartment_ocid}"
  instance_id     = "${oci_core_instance.broker.*.id[count.index % var.broker["node_count"]]}"
  volume_id       = "${oci_core_volume.broker.*.id[count.index]}"

  provisioner "remote-exec" {
    connection {
      agent               = false
      timeout             = "30m"
      host                = "${element(oci_core_instance.broker.*.private_ip, count.index % var.broker["node_count"] )}"
      user                = "${var.ssh_user}"
      private_key         = "${var.ssh_private_key}"
      bastion_host        = "${oci_core_instance.bastion.*.public_ip[0]}"
      bastion_port        = "22"
      bastion_user        = "${var.ssh_user}"
      bastion_private_key = "${var.ssh_private_key}"
    }

    inline = [
      "sudo -s bash -c 'set -x && iscsiadm -m node -o new -T ${self.iqn} -p ${self.ipv4}:${self.port}'",
      "sudo -s bash -c 'set -x && iscsiadm -m node -o update -T ${self.iqn} -n node.startup -v automatic '",
      "sudo -s bash -c 'set -x && iscsiadm -m node -T ${self.iqn} -p ${self.ipv4}:${self.port} -l '",
    ]
  }

}

output "Kafka Broker Private IPs" {
  value = "${join(",", oci_core_instance.broker.*.private_ip)}"
}
