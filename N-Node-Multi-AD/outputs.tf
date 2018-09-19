output "1 - BrokerNode 1 SSH login " {
value = <<END
	ssh -i ~/.ssh/id_rsa opc@${data.oci_core_vnic.broker_node_vnic.public_ip_address}
END
}

output "2 - WorkerNode 1 SSH login " {
value = <<END
        ssh -i ~/.ssh/id_rsa opc@${data.oci_core_vnic.worker_node_vnic.public_ip_address}
END
}

output "3 - Control Center  " {
value = <<END
        http://${data.oci_core_vnic.worker_node_vnic.public_ip_address}:9021/
END
}


#output "4 - All Broker Node IPs " {
#value = <<END
#        ${data.oci_core_vnic.all_broker_nodes_first_vnic.*.public_ip_address}
#END
#}


