# Configure the Azure provider
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 2.98"
    }
  }

  required_version = ">= 1.1.0"
}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = "westeurope"
tags = {
     Environment = "Terraform Getting Started"
     Team = "DevOps"
   }
}


# Create the network VNET
resource "azurerm_virtual_network" "network-vnet" {
  name                = "petrus-vnet"
  address_space       = ["10.0.0.0/16"]
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
}

# Create a subnet for Network
resource "azurerm_subnet" "network-subnet" {
  name                 = "petrus-subnet"
  address_prefixes       = ["10.0.0.0/24"]
  virtual_network_name = azurerm_virtual_network.network-vnet.name
  resource_group_name  = azurerm_resource_group.rg.name
}

resource "azurerm_storage_account" "storageacc" {
  depends_on=[azurerm_resource_group.rg]
  name                     = "petrus1234testi"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "GRS"
}


resource "azurerm_storage_container" "container" {
  depends_on=[azurerm_storage_account.storageacc]
  name                  = "content"
  storage_account_name  = azurerm_storage_account.storageacc.name
  container_access_type = "private"
}

resource "azurerm_storage_management_policy" "storage_management" {
  storage_account_id ="${azurerm_storage_account.storageacc.id}"

  rule {
    name = "rule1"
    enabled = true
    filters {
      blob_types = ["blockBlob"]
    }
    actions {
      base_blob {
        delete_after_days_since_modification_greater_than = 1
      }
  }
}
}



# Generate randon name for virtual machine
resource "random_string" "random-linux-vm" {
  length  = 8
  special = false
  lower   = true
  upper   = false
  number  = true
}
# Create Security Group to access web
resource "azurerm_network_security_group" "web-linux-vm-nsg" {
  depends_on=[azurerm_resource_group.rg]
  name = "web-linux-vm-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  security_rule {
    name                       = "allow-ssh"
    description                = "allow-ssh"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "allow-http"
    description                = "allow-http"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }
}

# Associate the web NSG with the subnet
resource "azurerm_subnet_network_security_group_association" "web-linux-vm-nsg-association" {
  depends_on=[azurerm_network_security_group.web-linux-vm-nsg]
  subnet_id                 = azurerm_subnet.network-subnet.id
  network_security_group_id = azurerm_network_security_group.web-linux-vm-nsg.id
}

# Get a Static Public IP
resource "azurerm_public_ip" "web-linux-vm-ip" {
  depends_on=[azurerm_resource_group.rg]
  name = "linux-${random_string.random-linux-vm.result}-vm-ip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
}

# Create Network Card for web VM
resource "azurerm_network_interface" "web-linux-vm-nic" {
  depends_on=[azurerm_public_ip.web-linux-vm-ip]
  name = "linux-${random_string.random-linux-vm.result}-vm-nic"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  
  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.network-subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.web-linux-vm-ip.id
  }
}

# Data template Bash bootstrapping file
data "template_file" "linux-vm-cloud-init" {
  template = file("azure-user-data.sh")
}

# Create Linux VM with web server
resource "azurerm_linux_virtual_machine" "web-linux-vm" {
  depends_on=[azurerm_network_interface.web-linux-vm-nic]
  name = "linux-${random_string.random-linux-vm.result}-vm"
  location              = azurerm_resource_group.rg.location
  resource_group_name   = azurerm_resource_group.rg.name
  network_interface_ids = [azurerm_network_interface.web-linux-vm-nic.id]
  size                  = "Standard_B2s"
  source_image_reference {
    offer     = "UbuntuServer"
    publisher = "Canonical"
    sku       = "18.04-LTS"
    version   = "latest"
  }
  os_disk {
   name = "linux-${random_string.random-linux-vm.result}-vm-os-disk"
   caching              = "ReadWrite"
   storage_account_type = "Standard_LRS"
  }
  computer_name = "linux-${random_string.random-linux-vm.result}-vm"
  admin_username = "petrus"
  admin_password = random_password.web-linux-vm-password.result
  disable_password_authentication = false
  custom_data    = base64encode(data.template_file.linux-vm-cloud-init.rendered)
}

# Generate random password
resource "random_password" "web-linux-vm-password" {
  length           = 16
  min_upper        = 2
  min_lower        = 2
  min_special      = 2
  number           = true
  special          = true
  override_special = "!@#$%&"
}

resource "azurerm_postgresql_server" "psql" {
  name                = "postgresql-server-1"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  sku_name = "B_Gen5_2"

  storage_mb                   = 5120
  backup_retention_days        = 7
  geo_redundant_backup_enabled = false
  auto_grow_enabled            = true

  administrator_login          = "psqladmin"
  administrator_login_password = "random_password.web-linux-vm-password.result"
  version                      = "9.5"
  ssl_enforcement_enabled      = true
}