resource "oci_core_instance" "broker" {
  display_name        = "broker-${count.index}"
  compartment_id      = var.compartment_ocid
  availability_domain = data.oci_identity_availability_domains.availability_domains.availability_domains[0]["name"]
  shape               = var.broker["shape"]
  subnet_id           = oci_core_subnet.subnet.id
  fault_domain        = "FAULT-DOMAIN-${count.index % 3 + 1}"

  source_details {
    source_id   = var.images[var.region]
    source_type = "image"
  }

  create_vnic_details {
    subnet_id      = oci_core_subnet.subnet.id
    hostname_label = "broker-${count.index}"
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data = base64encode(
      join(
        "\n",
        [
          "#!/usr/bin/env bash",
          "version=${var.confluent["version"]}",
          "edition=${var.confluent["edition"]}",
          "zookeeperNodeCount=${var.zookeeper["node_count"]}",
          "brokerNodeCount=${var.broker["node_count"]}",
          "brokerDiskCount=${var.broker["disk_count"]}",
          "schemaRegistryNodeCount=${var.schema_registry["node_count"]}",
          file("../scripts/firewall.sh"),
          file("../scripts/install.sh"),
          file("../scripts/disks.sh"),
          file("../scripts/kafka_deploy_helper.sh"),
          file("../scripts/broker.sh"),
        ],
      ),
    )
  }

  count = var.broker["node_count"]
}

resource "oci_core_volume" "broker" {
  count               = var.broker["node_count"] * var.broker["disk_count"]
  availability_domain = data.oci_identity_availability_domains.availability_domains.availability_domains[0]["name"]
  compartment_id      = var.compartment_ocid
  display_name        = "broker${count.index % var.broker["node_count"]}-volume${floor(count.index / var.broker["node_count"])}"
  size_in_gbs         = var.broker["disk_size"]
}

resource "oci_core_volume_attachment" "broker" {
  count           = var.broker["node_count"] * var.broker["disk_count"]
  attachment_type = "iscsi"
  compartment_id  = var.compartment_ocid
  instance_id     = oci_core_instance.broker[count.index % var.broker["node_count"]].id
  volume_id       = oci_core_volume.broker[count.index].id
}

output "broker_public_ips" {
  value = join(",", oci_core_instance.broker.*.public_ip)
}
