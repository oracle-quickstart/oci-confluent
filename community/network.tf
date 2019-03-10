data "oci_identity_availability_domains" "availability_domains" {
  compartment_id = "${var.compartment_ocid}"
}

data "oci_identity_fault_domains" "fault_domains" {
    availability_domain = "${lookup(data.oci_identity_availability_domains.availability_domains.availability_domains[0], "name")}"
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

resource "oci_core_nat_gateway" "nat_gateway" {
  compartment_id = "${var.compartment_ocid}"
  vcn_id         = "${oci_core_virtual_network.virtual_network.id}"
  display_name   = "nat_gateway"
}

resource "oci_core_route_table" "public_route_table" {
  display_name   = "public_route_table"
  compartment_id = "${var.compartment_ocid}"
  vcn_id         = "${oci_core_virtual_network.virtual_network.id}"

  route_rules {
    destination       = "0.0.0.0/0"
    network_entity_id = "${oci_core_internet_gateway.internet_gateway.id}"
  }
}

resource "oci_core_route_table" "private_route_table" {
  compartment_id = "${var.compartment_ocid}"
  vcn_id         = "${oci_core_virtual_network.virtual_network.id}"
  display_name   = "private_route_table"

  route_rules {
    destination       = "0.0.0.0/0"
    network_entity_id = "${oci_core_nat_gateway.nat_gateway.id}"
    
  }
}


resource "oci_core_security_list" "public_security_list" {
  display_name   = "public_security_list"
  compartment_id = "${var.compartment_ocid}"
  vcn_id         = "${oci_core_virtual_network.virtual_network.id}"

  egress_security_rules = [{
    protocol    = "All"
    destination = "0.0.0.0/0"
  }]

  ingress_security_rules = [{
    protocol = "All"
    source   = "0.0.0.0/0"
  }]
  
  ingress_security_rules = [{
    tcp_options {
      "max" = 22
      "min" = 22
    }
    protocol = "6"
    source = "0.0.0.0/0"
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


}

resource "oci_core_security_list" "private_security_list" {
  display_name   = "private_security_list"
  compartment_id = "${var.compartment_ocid}"
  vcn_id         = "${oci_core_virtual_network.virtual_network.id}"

  egress_security_rules = [{
    destination = "0.0.0.0/0"
    protocol    = "all"
  }]

  ingress_security_rules = [{
    tcp_options {
      "max" = 22
      "min" = 22
    }
    protocol = "6"
    source   = "${var.vpc-cidr}"
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
      "max" = 9092
      "min" = 9092
    }
    protocol = "6"
    source   = "${var.vpc-cidr}"
  }]

  ingress_security_rules = [{
    protocol = "All"
    source = "${var.vpc-cidr}"
  }]

}

/*
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
*/

resource "oci_core_subnet" "private_subnet" {
  display_name        = "private_subnet"
  compartment_id      = "${var.compartment_ocid}"
  availability_domain = "${lookup(data.oci_identity_availability_domains.availability_domains.availability_domains[0], "name")}"
  cidr_block          = "${cidrsubnet(var.vpc-cidr, 8, 1)}"
  vcn_id              = "${oci_core_virtual_network.virtual_network.id}"
  route_table_id      = "${oci_core_route_table.private_route_table.id}"
  security_list_ids   = ["${oci_core_security_list.private_security_list.id}"]
  dhcp_options_id     = "${oci_core_virtual_network.virtual_network.default_dhcp_options_id}"
  dns_label           = "private"
  prohibit_public_ip_on_vnic = "true"
}


resource "oci_core_subnet" "public_subnet" {
  display_name        = "public_subnet"
  compartment_id      = "${var.compartment_ocid}"
  availability_domain = "${lookup(data.oci_identity_availability_domains.availability_domains.availability_domains[0], "name")}"
  cidr_block          = "${cidrsubnet(var.vpc-cidr, 8, 0)}"
  vcn_id              = "${oci_core_virtual_network.virtual_network.id}"
  route_table_id      = "${oci_core_route_table.public_route_table.id}"
  security_list_ids   = ["${oci_core_security_list.public_security_list.id}"]
  dhcp_options_id     = "${oci_core_virtual_network.virtual_network.default_dhcp_options_id}"
  dns_label           = "public"
}

