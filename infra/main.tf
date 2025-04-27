provider "azurerm" {
  features {}
}

terraform {
  required_providers {
    azuread = {
      source  = "hashicorp/azuread"
    }
  }
}


provider "azuread" {
  tenant_id = "fbc822d7-87fc-4802-ba1e-05dd03030c31"
}

resource "azurerm_resource_group" "rg" {
  name     = "rg-azure-poc"
  location = "East US 2"
}

module "network" {
  source              = "Azure/network/azurerm"
  resource_group_name = azurerm_resource_group.rg.name
  vnet_name           = "poc-vnet"
  address_space       = "10.0.0.0/16"
  subnet_prefixes     = ["10.0.1.0/24", "10.0.2.0/24"]
  subnet_names        = ["public-subnet-7a8c74a4", "private-subnet-7a8c74a4"]
  use_for_each        = true

  depends_on = [azurerm_resource_group.rg]
}

# Subnet Resource (Delegated Private Subnet)
resource "azurerm_subnet" "delegated_private_subnet" {
  name                 = "private-subnet-7a8c74a4"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = module.network.vnet_name
  address_prefixes     = ["10.0.2.0/24"]

  depends_on = [module.network]
}

# Container Registry
resource "azurerm_container_registry" "acr" {
  name                = "pwsacr7a8c74a4"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "Basic"
  admin_enabled       = true
}

output "acr_login_server" {
  value = azurerm_container_registry.acr.login_server
}


data "azuread_service_principal" "githubactionsp" {
  display_name = "githubactionsp"
}


resource "azurerm_role_assignment" "acr_push_access" {
  principal_id         = data.azuread_service_principal.githubactionsp.object_id
  role_definition_name = "AcrPush"
  scope                = azurerm_container_registry.acr.id
}
