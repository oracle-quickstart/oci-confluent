resource "oci_core_instance" "zookeeper" {
  display_name        = "zookeeper-${count.index}"
  compartment_id      = "${var.compartment_ocid}"
  availability_domain = "${lookup(data.oci_identity_availability_domains.availability_domains.availability_domains[0],"name")}"
  shape               = "${var.zookeeper["shape"]}"
  subnet_id           = "${oci_core_subnet.subnet.id}"

  source_details {
    source_id   = "${var.images[var.region]}"
    source_type = "image"
  }

  create_vnic_details {
    subnet_id        = "${oci_core_subnet.subnet.id}"
    hostname_label   = "zookeeper-${count.index}"
  }

  metadata {
    ssh_authorized_keys = "${var.ssh_public_key}"
    user_data = "${base64encode(join("\n", list(
      "#!/usr/bin/env bash",
      "version=${var.confluent["version"]}",
      "version=${var.confluent["edition"]}",
      file("../scripts/install.sh"),
      file("../scripts/zookeeper.sh")
    )))}"
  }

  count = "${var.zookeeper["node_count"]}"
}

output "Zookeeper Public IPs" {
  value = "${join(",", oci_core_instance.zookeeper.*.public_ip)}"
}
