# Configure the Azure provider
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 2.65"
    }
    random = {
      source = "hashicorp/random"
      version = "3.1.0"
    }
    tls = {
      source = "hashicorp/tls"
      version = "3.1.0"
    }
  }
}


provider "tls" {

}
provider "random" {

}
provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "rg" {
  name     = "awebsite-terraform-group"
  location = "eastus"
}

resource "azurerm_virtual_network" "vnet" {
    name = "sample-vnet"
    address_space = [ "10.0.0.0/16" ]
    location = "eastus"
    resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "firstsubnet" {
    name = "firstsubnet"
    resource_group_name = azurerm_resource_group.rg.name
    virtual_network_name = azurerm_virtual_network.vnet.name
    address_prefixes = ["10.0.1.0/24"]
}

resource "azurerm_public_ip" "awebsite-vm-ip" {
    name = "vm-ip"
    location = "eastus"
    resource_group_name = azurerm_resource_group.rg.name
    allocation_method = "Dynamic"
    sku = "Basic"
}

resource "azurerm_network_interface" "awebsite-vm-nic" {
    name = "vm-nic"
    location = "eastus"
    resource_group_name = azurerm_resource_group.rg.name

    ip_configuration {
      name = "ipconfig1"
      subnet_id = azurerm_subnet.firstsubnet.id
      private_ip_address_allocation = "Dynamic"
      public_ip_address_id = azurerm_public_ip.awebsite-vm-ip.id
    }
}
resource "azurerm_network_security_group" "awebsitensg" {
    name                = "myNetworkSecurityGroup"
    location            = "eastus"
    resource_group_name = azurerm_resource_group.rg.name

    security_rule {
        name                       = "SSH"
        priority                   = 1001
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "22"
        source_address_prefix      = "*"
        destination_address_prefix = "*"
    }
}

resource "azurerm_network_interface_security_group_association" "example" {
    network_interface_id      = azurerm_network_interface.awebsite-vm-nic.id
    network_security_group_id = azurerm_network_security_group.awebsitensg.id
}

resource "random_id" "randomId" {
    keepers = {
        resource_group = azurerm_resource_group.rg.name
    }

    byte_length = 8
}

resource "azurerm_storage_account" "mystorageaccount" {
    name                        = "diag${random_id.randomId.hex}"
    resource_group_name         = azurerm_resource_group.rg.name
    location                    = "eastus"
    account_tier                = "Standard"
    account_replication_type    = "LRS"
}

resource "tls_private_key" "example_ssh" {
  algorithm = "RSA"
  rsa_bits = 4096
}
output "tls_private_key" { 
    value = tls_private_key.example_ssh.private_key_pem 
    sensitive = true
}
resource "azurerm_linux_virtual_machine" "awebsitevm" {
    name                  = "awebsiteVM"
    location              = "eastus"
    resource_group_name   = azurerm_resource_group.rg.name
    network_interface_ids = [azurerm_network_interface.awebsite-vm-nic.id]
    size                  = "Standard_DS1_v2"

    os_disk {
        name              = "myOsDisk"
        caching           = "ReadWrite"
        storage_account_type = "Premium_LRS"
    }

    source_image_reference {
        publisher = "Canonical"
        offer     = "UbuntuServer"
        sku       = "18.04-LTS"
        version   = "latest"
    }

    computer_name  = "myvm"
    admin_username = "azureuser"
    disable_password_authentication = true

    admin_ssh_key {
        username       = "azureuser"
        public_key     = tls_private_key.example_ssh.public_key_openssh
    }

    boot_diagnostics {
        storage_account_uri = azurerm_storage_account.mystorageaccount.primary_blob_endpoint
    }

}