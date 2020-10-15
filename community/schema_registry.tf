resource "oci_core_instance" "schema_registry" {
  display_name        = "schema_registry-${count.index}"
  compartment_id      = var.compartment_ocid
  availability_domain = local.availability_domain
  shape               = var.broker["shape"]
  subnet_id           = oci_core_subnet.subnet.id
  fault_domain        = "FAULT-DOMAIN-${count.index % 3 + 1}"

  source_details {
    source_id   = var.images[var.region]
    source_type = "image"
  }

  create_vnic_details {
    subnet_id      = oci_core_subnet.subnet.id
    hostname_label = "schema-registry-${count.index}"
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
          "schemaRegistryNodeCount=${var.schema_registry["node_count"]}",
          file("../scripts/firewall.sh"),
          file("../scripts/install.sh"),
          file("../scripts/kafka_deploy_helper.sh"),
          file("../scripts/schema_registry.sh"),
        ],
      ),
    )
  }

  count = var.schema_registry["node_count"]
}

output "schema_registry_public_ips" {
  value = join(",", oci_core_instance.schema_registry.*.public_ip)
}

output "schema_registry_url" {
  value = <<END
http://${oci_core_instance.schema_registry[0].private_ip}:8081/
END

}
