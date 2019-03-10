/* bastion instance */

resource "oci_core_instance" "bastion" {
  display_name        = "bastion-${count.index}"
  availability_domain = "${lookup(data.oci_identity_availability_domains.availability_domains.availability_domains[0],"name")}"
  compartment_id      = "${var.compartment_ocid}"
  shape               = "${var.bastion["shape"]}"

  source_details {
    source_id   = "${var.images[var.region]}"
    source_type = "image"
  }

  create_vnic_details {
    subnet_id      = "${oci_core_subnet.public_subnet.id}"
    hostname_label = "bastion-${count.index}"
  }

  metadata {
    ssh_authorized_keys = "${var.ssh_public_key}"

    user_data = "${base64encode(join("\n", list(
      "#!/usr/bin/env bash",
      file("../scripts/bastion.sh")
    )))}"
  }

  count = "${var.bastion["node_count"]}"
}

output "Bastion Public IPs" {
  value = "${join(",", oci_core_instance.bastion.*.public_ip)}"
}
