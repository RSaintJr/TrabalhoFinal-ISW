# cloud-infrastructure/terraform/main.tf
terraform {
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }
}

provider "oci" {
  tenancy_ocid     = var.tenancy_ocid
  user_ocid        = var.user_ocid
  fingerprint      = var.fingerprint
  private_key_path = var.private_key_path
  region           = var.region
}

# Variables
variable "tenancy_ocid" {}
variable "user_ocid" {}
variable "fingerprint" {}
variable "private_key_path" {}
variable "region" { default = "us-ashburn-1" }
variable "compartment_ocid" {}
variable "ssh_public_key_path" {}
variable "ssh_private_key_path" {}
variable "github_repo" {
  description = "URL do repositório Git do projeto"
  type        = string
  default     = "https://github.com/seu-usuario/iot-agriculture-monitoring.git"
}
variable "github_branch" {
  description = "Branch do repositório Git para usar"
  type        = string
  default     = "main"
}

# VCN (Virtual Cloud Network)
resource "oci_core_vcn" "iot_agriculture_vcn" {
  compartment_id = var.compartment_ocid
  cidr_block     = "10.0.0.0/16"
  display_name   = "iot-agriculture-vcn"
  dns_label      = "iotagriculture"
}

# Internet Gateway
resource "oci_core_internet_gateway" "iot_agriculture_igw" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.iot_agriculture_vcn.id
  display_name   = "iot-agriculture-igw"
}

# NAT Gateway
resource "oci_core_nat_gateway" "iot_agriculture_nat" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.iot_agriculture_vcn.id
  display_name   = "iot-agriculture-nat"
}

# Public Subnet
resource "oci_core_subnet" "public_subnet" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.iot_agriculture_vcn.id
  cidr_block     = "10.0.1.0/24"
  display_name   = "public-subnet"
  dns_label      = "public"
  
  route_table_id = oci_core_route_table.public_route_table.id
  security_list_ids = [oci_core_security_list.public_security_list.id]
}

# Private Subnet
resource "oci_core_subnet" "private_subnet" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.iot_agriculture_vcn.id
  cidr_block     = "10.0.2.0/24"
  display_name   = "private-subnet"
  dns_label      = "private"
  
  route_table_id = oci_core_route_table.private_route_table.id
  security_list_ids = [oci_core_security_list.private_security_list.id]
  prohibit_public_ip_on_vnic = true
}

# Route Tables
resource "oci_core_route_table" "public_route_table" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.iot_agriculture_vcn.id
  display_name   = "public-route-table"
  
  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.iot_agriculture_igw.id
  }
}

resource "oci_core_route_table" "private_route_table" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.iot_agriculture_vcn.id
  display_name   = "private-route-table"
  
  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_nat_gateway.iot_agriculture_nat.id
  }
}

# Security Lists
resource "oci_core_security_list" "public_security_list" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.iot_agriculture_vcn.id
  display_name   = "public-security-list"
  
  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
  }
  
  ingress_security_rules {
    protocol = "6" # TCP
    source   = "0.0.0.0/0"
    
    tcp_options {
      min = 443
      max = 443
    }
  }
  
  ingress_security_rules {
    protocol = "6" # TCP
    source   = "0.0.0.0/0"
    
    tcp_options {
      min = 80
      max = 80
    }
  }
  
  ingress_security_rules {
    protocol = "6" # TCP
    source   = "0.0.0.0/0"
    
    tcp_options {
      min = 22
      max = 22
    }
  }
  
  ingress_security_rules {
    protocol = "6" # TCP
    source   = "0.0.0.0/0"
    
    tcp_options {
      min = 3000
      max = 3000
    }
    description = "API Gateway"
  }
  
  ingress_security_rules {
    protocol = "6" # TCP
    source   = "0.0.0.0/0"
    
    tcp_options {
      min = 8080
      max = 8080
    }
    description = "Dashboard"
  }
  
  ingress_security_rules {
    protocol = "6" # TCP
    source   = "0.0.0.0/0"
    
    tcp_options {
      min = 6379
      max = 6379
    }
    description = "Redis"
  }
  
  ingress_security_rules {
    protocol = "6" # TCP
    source   = "0.0.0.0/0"
    
    tcp_options {
      min = 8088
      max = 8088
    }
    description = "Nginx Frontend"
  }
}

resource "oci_core_security_list" "private_security_list" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.iot_agriculture_vcn.id
  display_name   = "private-security-list"
  
  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
  }
  
  ingress_security_rules {
    protocol = "6" # TCP
    source   = "10.0.0.0/16"
    
    tcp_options {
      min = 3306
      max = 3306
    }
  }
  
  ingress_security_rules {
    protocol = "6" # TCP
    source   = "10.0.0.0/16"
    
    tcp_options {
      min = 27017
      max = 27017
    }
  }
}

# Random password for MySQL
resource "random_password" "mysql_root_password" {
  length  = 16
  special = true
}

# Random password for API key
resource "random_password" "api_key" {
  length  = 32
  special = false
}

# Compute Instance
resource "oci_core_instance" "iot_agriculture_instance" {
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  compartment_id      = var.compartment_ocid
  display_name        = "iot-agriculture-server"
  shape               = "VM.Standard.E2.1.Micro"
  
  create_vnic_details {
    subnet_id        = oci_core_subnet.public_subnet.id
    display_name     = "primaryvnic"
    assign_public_ip = true
  }
  
  source_details {
    source_type = "image"
    source_id   = data.oci_core_images.ubuntu_images.images[0].id
    boot_volume_size_in_gbs = 100
  }
  
  metadata = {
    ssh_authorized_keys = file(var.ssh_public_key_path)
    user_data = base64encode(templatefile("${path.module}/cloud-init.yaml", {
      mysql_root_password = random_password.mysql_root_password.result,
      github_repo        = var.github_repo,
      github_branch      = var.github_branch
    }))
  }
}

# Data sources
data "oci_identity_availability_domains" "ads" {
  compartment_id = var.compartment_ocid
}

data "oci_core_images" "ubuntu_images" {
  compartment_id           = var.compartment_ocid
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "22.04"
  shape                    = "VM.Standard.E2.1.Micro"
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

# Object Storage Bucket
resource "oci_objectstorage_bucket" "iot_agriculture_bucket" {
  compartment_id = var.compartment_ocid
  name           = "iot-agriculture-data"
  namespace      = data.oci_objectstorage_namespace.namespace.namespace
  
  access_type = "NoPublicAccess"
  
  versioning = "Disabled"
  
  retention_rules {
    display_name = "data-retention"
    
    duration {
      time_amount = 365
      time_unit   = "DAYS"
    }
  }
}

data "oci_objectstorage_namespace" "namespace" {
  compartment_id = var.compartment_ocid
}

# OCI Vault
resource "oci_kms_vault" "iot_agriculture_vault" {
  compartment_id   = var.compartment_ocid
  display_name     = "iot-agriculture-vault"
  vault_type       = "DEFAULT"
}

resource "oci_kms_key" "iot_agriculture_key" {
  compartment_id = var.compartment_ocid
  display_name   = "iot-agriculture-key"
  
  key_shape {
    algorithm = "AES"
    length    = 32
  }
  
  management_endpoint = oci_kms_vault.iot_agriculture_vault.management_endpoint
}

# Vault Secrets
resource "oci_vault_secret" "mysql_password" {
  compartment_id = var.compartment_ocid
  secret_name    = "mysql-root-password"
  vault_id       = oci_kms_vault.iot_agriculture_vault.id
  key_id         = oci_kms_key.iot_agriculture_key.id
  
  secret_content {
    content_type = "BASE64"
    content      = base64encode(random_password.mysql_root_password.result)
  }
}

resource "oci_vault_secret" "api_key" {
  compartment_id = var.compartment_ocid
  secret_name    = "api-gateway-key"
  vault_id       = oci_kms_vault.iot_agriculture_vault.id
  key_id         = oci_kms_key.iot_agriculture_key.id
  
  secret_content {
    content_type = "BASE64"
    content      = base64encode(random_password.api_key.result)
  }
}

# Load Balancer
resource "oci_load_balancer" "iot_agriculture_lb" {
  compartment_id = var.compartment_ocid
  display_name   = "iot-agriculture-lb"
  shape          = "flexible"
  
  subnet_ids = [oci_core_subnet.public_subnet.id]
  
  shape_details {
    maximum_bandwidth_in_mbps = 100
    minimum_bandwidth_in_mbps = 10
  }
  
  is_private = false
}

resource "oci_load_balancer_backend_set" "iot_agriculture_backend_set" {
  load_balancer_id = oci_load_balancer.iot_agriculture_lb.id
  name             = "iot-agriculture-backend-set"
  policy           = "ROUND_ROBIN"
  
  health_checker {
    protocol            = "HTTP"
    port                = 3000
    url_path            = "/health"
    return_code         = 200
    interval_ms         = 30000
    timeout_in_millis   = 3000
    retries             = 3
  }
}

resource "oci_load_balancer_backend" "iot_agriculture_backend" {
  load_balancer_id = oci_load_balancer.iot_agriculture_lb.id
  backendset_name  = oci_load_balancer_backend_set.iot_agriculture_backend_set.name
  ip_address       = oci_core_instance.iot_agriculture_instance.private_ip
  port             = 3000
  backup           = false
  drain            = false
  offline          = false
  weight           = 1
}

resource "oci_load_balancer_listener" "iot_agriculture_listener" {
  load_balancer_id         = oci_load_balancer.iot_agriculture_lb.id
  name                     = "iot-agriculture-listener"
  default_backend_set_name = oci_load_balancer_backend_set.iot_agriculture_backend_set.name
  port                     = 80
  protocol                 = "HTTP"
  
  connection_configuration {
    idle_timeout_in_seconds = 300
  }
}

# Block Volume para dados persistentes
resource "oci_core_volume" "iot_agriculture_data" {
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  compartment_id      = var.compartment_ocid
  display_name        = "iot-agriculture-data"
  size_in_gbs        = 50
}

resource "oci_core_volume_attachment" "iot_agriculture_data_attachment" {
  attachment_type = "paravirtualized"
  instance_id     = oci_core_instance.iot_agriculture_instance.id
  volume_id       = oci_core_volume.iot_agriculture_data.id
}

# Outputs
output "public_ip" {
  value = oci_core_instance.iot_agriculture_instance.public_ip
}

output "load_balancer_ip" {
  value = oci_load_balancer.iot_agriculture_lb.ip_address_details[0].ip_address
}

output "bucket_name" {
  value = oci_objectstorage_bucket.iot_agriculture_bucket.name
}

output "vault_id" {
  value = oci_kms_vault.iot_agriculture_vault.id
}