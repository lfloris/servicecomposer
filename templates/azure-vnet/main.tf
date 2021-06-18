#################################################################
# Terraform template that will deploy:
#    * Windows Server VM on Microsoft Azure
#
# Version: 2.4
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Licensed Materials - Property of IBM
#
# ©Copyright IBM Corp. 2020.
#
#################################################################

terraform {
  required_version = ">= 0.12"
}

#########################################################
# Define the Azure provider
#########################################################
provider "azurerm" {
  #azurerm_subnet uses address_prefixes from 2.9.0
  #so pin this template to >= 2.9.0
  version = ">= 2.9.0"
  features {}
}

#########################################################
# Helper module for tagging
#########################################################
module "camtags" {
  source = "../Modules/camtags"
}

#########################################################
# Define the variables
#########################################################
variable "azure_region" {
  description = "Azure region to deploy infrastructure resources"
  default     = "West US"
}

variable "name_prefix" {
  description = "Prefix of names for Azure resources"
  default     = "singleVM"
}

#########################################################
# Deploy the network resources
#########################################################
resource "random_id" "default" {
  byte_length = "4"
}

resource "azurerm_resource_group" "default" {
  name     = "${var.name_prefix}-${random_id.default.hex}-rg"
  location = var.azure_region
  tags     = module.camtags.tagsmap
}

resource "azurerm_virtual_network" "default" {
  name                = "${var.name_prefix}-${random_id.default.hex}-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = var.azure_region
  resource_group_name = azurerm_resource_group.default.name

  tags = {
    environment = "Terraform Basic VM"
  }
}

resource "azurerm_subnet" "vm" {
  name                 = "${var.name_prefix}-subnet-${random_id.default.hex}-vm"
  resource_group_name  = azurerm_resource_group.default.name
  virtual_network_name = azurerm_virtual_network.default.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_network_security_group" "vm" {
  depends_on		  = ["azurerm_network_interface.vm"]
  name                = "${var.name_prefix}-${random_id.default.hex}-vm-nsg"
  location            = var.azure_region
  resource_group_name = azurerm_resource_group.default.name
  tags                = module.camtags.tagsmap

  security_rule {
    name                       = "ssh-allow"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "custom-tcp-allow"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}