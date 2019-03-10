resource "oci_core_instance" "broker" {
  display_name        = "broker-${count.index}"
  compartment_id      = "${var.compartment_ocid}"
  availability_domain = "${lookup(data.oci_identity_availability_domains.availability_domains.availability_domains[0],"name")}"
  shape               = "${var.broker["shape"]}"
  subnet_id           = "${oci_core_subnet.subnet.id}"
  fault_domain = "${lookup(data.oci_identity_fault_domains.fault_domains.fault_domains[count.index%3],"name")}"

  source_details {
    source_id   = "${var.images[var.region]}"
    source_type = "image"
  }

  create_vnic_details {
    subnet_id           = "${oci_core_subnet.subnet.id}"
    hostname_label = "broker-${count.index}"
    assign_public_ip = "false"
  }

  metadata {
    ssh_authorized_keys = "${var.ssh_public_key}"

    user_data = "${base64encode(join("\n", list(
      "#!/usr/bin/env bash",
      file("../scripts/broker.sh")
    )}"
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

output "Kafka Broker Private IPs" {
  value = "${join(",", oci_core_instance.broker.*.private_ip)}"
}
