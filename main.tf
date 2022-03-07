# Configure the Azure provider
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 2.65"
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
    offer     = "debian-11"
    publisher = "Debian"
    sku       = "11-gen2"
    version   = "latest"
  }
  os_disk {
   name = "linux-${random_string.random-linux-vm.result}-vm-os-disk"
   caching              = "ReadWrite"
   storage_account_type = "Standard_LRS"
  }
  computer_name = "linux-${random_string.random-linux-vm.result}-vm"
  admin_username = "petrus"
  admin_password = var.admin_password
  custom_data = base64encode(data.template_file.linux-vm-cloud-init.rendered)
  disable_password_authentication = false
}