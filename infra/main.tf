
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

# # Subnet Resource (Delegated Private Subnet)
# resource "azurerm_subnet" "delegated_private_subnet" {
#   name                 = "private-subnet-7a8c74a4"
#   resource_group_name  = azurerm_resource_group.rg.name
#   virtual_network_name = module.network.vnet_name
#   address_prefixes     = ["10.0.2.0/24"]

#   depends_on = [module.network]
# }

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

resource "azurerm_kubernetes_cluster" "aks" {
  name                = "aks-poc-cluster"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = "akspoc"
  node_resource_group = "aks-nodes-rg"

  default_node_pool {
    name           = "default"
    node_count     = 1
    vm_size        = "Standard_B2s"
    vnet_subnet_id = module.network.vnet_subnets[1]
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin = "azure"
    service_cidr   = "10.10.0.0/16"
    dns_service_ip = "10.10.0.10"
  }

  depends_on = [
    azurerm_container_registry.acr,
    module.network
  ]
}

resource "azurerm_role_assignment" "aks_acr_pull" {
  principal_id         = azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
  role_definition_name = "AcrPull"
  scope                = azurerm_container_registry.acr.id
}

provider "kubernetes" {
  host                   = azurerm_kubernetes_cluster.aks.kube_config.0.host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.cluster_ca_certificate)
}


resource "kubernetes_deployment" "myapp" {
  metadata {
    name = "myapp-deployment"
    labels = {
      app = "myapp"
    }
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
          image = "${azurerm_container_registry.acr.login_server}/myapp:latest"
          port {
            container_port = 5000
          }
        }
      }
    }
  }

  depends_on = [
    azurerm_kubernetes_cluster.aks
  ]
}

resource "kubernetes_service" "myapp" {
  metadata {
    name = "myapp-service"
  }

  spec {
    selector = {
      app = "myapp"
    }

    port {
      port        = 80
      target_port = 5000
    }

    type = "LoadBalancer"
  }
}

output "kube_config" {
  value     = azurerm_kubernetes_cluster.aks.kube_config_raw
  sensitive = true
}

output "loadbalancer_ip" {
  value = kubernetes_service.myapp.status.0.load_balancer.0.ingress.0.ip
}
