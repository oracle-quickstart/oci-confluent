output "urls" {
  value = <<END
Schema Registry: curl http://${oci_core_instance.schema_registry[0].private_ip}:8081/
Connect: curl http://${oci_core_instance.connect[0].private_ip}:8083/connectors
REST: curl http://${oci_core_instance.rest[0].private_ip}:8082/topics
Control Center: http://${oci_core_instance.control_center[0].public_ip}:9021/
END

}
