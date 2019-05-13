

output "URLs: " {
value = <<END
Schema Registry: curl http://${oci_core_instance.schema_registry.*.private_ip[0]}:8081/
Connect: curl http://${oci_core_instance.connect.*.private_ip[0]}:8083/connectors
REST: curl http://${oci_core_instance.rest.*.private_ip[0]}:8082/topics
Control Center: http://${oci_core_instance.control_center.*.public_ip[0]}:9021/
END
}



