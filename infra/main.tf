provider "azurerm" {
  features {}
}

terraform {
  required_providers {
    azuread = {
      source = "hashicorp/azuread"
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

resource "azurerm_subnet" "delegated_private_subnet" {
  name                 = "private-subnet-7a8c74a4"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = module.network.vnet_name
  address_prefixes     = ["10.0.2.0/24"]

  depends_on = [module.network]
}

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

resource "azurerm_kubernetes_cluster" "aks_cluster" {
  name                = "aks-cluster"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = "aks-cluster"

  default_node_pool {
    name                  = "default"
    vm_size               = "Standard_DS2_v2"
    node_count            = 2
    vnet_subnet_id        = azurerm_subnet.delegated_private_subnet.id
  }

  network_profile {
    network_plugin    = "azure"
    load_balancer_sku = "standard"
    network_policy    = "azure"
  }

  identity {
    type = "SystemAssigned"
  }

  depends_on = [azurerm_subnet.delegated_private_subnet]
}

provider "kubernetes" {
  host                   = azurerm_kubernetes_cluster.aks_cluster.kube_config.0.host
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks_cluster.kube_config.0.cluster_ca_certificate)
  client_certificate     = base64decode(azurerm_kubernetes_cluster.aks_cluster.kube_config.0.client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.aks_cluster.kube_config.0.client_key)

  # Make sure provider waits for cluster
  depends_on = [azurerm_kubernetes_cluster.aks_cluster]
}

resource "kubernetes_deployment" "web_app_deployment" {
  metadata {
    name      = "myapp"
    namespace = "default"
  }

  spec {
    replicas = 2

    selector {
      match_labels = {
        app = "myapp"
      }
    }

    template {
      metadata {
        labels = {
          app = "myapp"
        }
      }

      spec {
        container {
          name  = "myapp"
          image = "pwsacr7a8c74a4.azurecr.io/myapp:latest"
          port {
            container_port = 5000
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "flask_crud_service" {
  metadata {
    name      = "flask-crud-service"
    namespace = "default"
  }

  spec {
    selector = {
      app = "myapp"
    }

    port {
      port        = 80          # External Port
      target_port = 5000         # Container Port
    }

    type = "LoadBalancer"
  }
}

output "web_app_url" {
  value = "http://${kubernetes_service.flask_crud_service.status.0.load_balancer.0.ingress.0.ip}"
  description = "Access your web app using this URL."
}
