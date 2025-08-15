provider "azurerm" {
  features {

  }
}

resource "azurerm_resource_group" "acidemobook" {
  name     = "demoBook"
  location = "West Europe"
}

variable "imageversion" {
  description = "Image tag to deploy"
  default     = "v1"
}

variable "acr-username" {
  description = "Image tag to deploy"
}

variable "acr-password" {
  sensitive = true
}

resource "azurerm_container_group" "aci-myapp" {
  name                = "aci-agent"
  location            = "West Europe"
  resource_group_name = azurerm_resource_group.acidemobook.name
  ip_address_type     = "Public"
  dns_name_label      = "myapp-demomc"
  os_type             = "Linux"

  container {
    name   = "myappdemo"
    image  = "acrdemomc.azurecr.io/demobook:${var.imageversion}"
    cpu    = "0.5"
    memory = "1.5"
    ports {
      port     = 80
      protocol = "TCP"
    }
  }
#   image_registry_credential {
#     server   = "acrdemomc.azurecr.io"
#     username = var.acr-username
#     password = var.acr-password
#   }
}