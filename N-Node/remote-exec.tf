resource "null_resource" "cf-cluster-setup" {
    depends_on = ["oci_core_instance.ZookeeperNode","oci_core_instance.BrokerNode","oci_core_instance.WorkerNode","oci_core_volume_attachment.BrokerAttachment1"]
    provisioner "file" {
      source = "/home/opc/.ssh/id_rsa"
      destination = "/home/opc/.ssh/id_rsa"
      connection {
        agent = false
        timeout = "10m"
        host = "${data.oci_core_vnic.broker_node_vnic.public_ip_address}"
        user = "opc"
        private_key = "${var.ssh_private_key}"
      }
    }
    provisioner "remote-exec" {
      connection {
        agent = false
        timeout = "10m"
        host = "${data.oci_core_vnic.broker_node_vnic.public_ip_address}"
        user = "opc"
        private_key = "${var.ssh_private_key}"
      }
      inline = [
	"chown opc:opc /home/opc/.ssh/id_rsa",
	"chmod 0600 /home/opc/.ssh/id_rsa",
	"sudo chmod +x /tmp/sbin/*.sh",
	"sudo /tmp/sbin/start.sh 2> /tmp/start.err",
	"echo SCREEN SESSION RUNNING ON cf-broker-1 AS ROOT"
	]
    }
}
