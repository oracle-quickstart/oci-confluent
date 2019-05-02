data "oci_identity_availability_domains" "availability_domains" {
  compartment_id = "${var.compartment_ocid}"
}

resource "oci_core_virtual_network" "virtual_network" {
  display_name   = "virtual_network"
  compartment_id = "${var.compartment_ocid}"
  cidr_block     = "10.0.0.0/16"
  dns_label      = "confluent"
}

resource "oci_core_internet_gateway" "internet_gateway" {
  display_name   = "internet_gateway"
  compartment_id = "${var.compartment_ocid}"
  vcn_id         = "${oci_core_virtual_network.virtual_network.id}"
}

resource "oci_core_route_table" "route_table" {
  display_name   = "route_table"
  compartment_id = "${var.compartment_ocid}"
  vcn_id         = "${oci_core_virtual_network.virtual_network.id}"

  route_rules {
    destination       = "0.0.0.0/0"
    network_entity_id = "${oci_core_internet_gateway.internet_gateway.id}"
  }
}

resource "oci_core_security_list" "security_list" {
  display_name   = "security_list"
  compartment_id = "${var.compartment_ocid}"
  vcn_id         = "${oci_core_virtual_network.virtual_network.id}"

  ingress_security_rules = [{
    tcp_options {
      "max" = 22
      "min" = 22
    }
    protocol = "6"
    source   = "0.0.0.0/0"
  }]

  ingress_security_rules = [{
    protocol = "All"
    source = "${var.vpc-cidr}"
  }]
  
  ingress_security_rules = [{
    tcp_options {
      "max" = 9092
      "min" = 9092
    }
    protocol = "6"
    source   = "0.0.0.0/0"
  }]

  ingress_security_rules = [{
    tcp_options {
      "max" = 2181
      "min" = 2181
    }
    protocol = "6"
    source   = "${var.vpc-cidr}"
  }]

 ingress_security_rules = [{
    tcp_options {
      "max" = 8081
      "min" = 8081
    }
    protocol = "6"
    source = "0.0.0.0/0"
  }]

  ingress_security_rules = [{
    tcp_options {
      "max" = 8082
      "min" = 8082
    }
    protocol = "6"
    source = "0.0.0.0/0"
  }]

  ingress_security_rules = [{
    tcp_options {
      "max" = 8083
      "min" = 8083
    }
    protocol = "6"
    source = "0.0.0.0/0"
  }]

  ingress_security_rules = [{
    tcp_options {
      "max" = 8088
      "min" = 8088
    }
    protocol = "6"
    source = "0.0.0.0/0"
  }]
  
  ingress_security_rules = [{
    tcp_options {
      "max" = 9021
      "min" = 9021
    }
    protocol = "6"
    source = "0.0.0.0/0"
  }]
  
  egress_security_rules = [{
    protocol    = "All"
    destination = "0.0.0.0/0"
  }]
  
}

resource "oci_core_subnet" "subnet" {
  display_name        = "subnet"
  compartment_id      = "${var.compartment_ocid}"
  availability_domain = "${lookup(data.oci_identity_availability_domains.availability_domains.availability_domains[0], "name")}"
  cidr_block          = "10.0.0.0/16"
  vcn_id              = "${oci_core_virtual_network.virtual_network.id}"
  route_table_id      = "${oci_core_route_table.route_table.id}"
  security_list_ids   = ["${oci_core_security_list.security_list.id}"]
  dhcp_options_id     = "${oci_core_virtual_network.virtual_network.default_dhcp_options_id}"
  dns_label           = "confluent"
}
