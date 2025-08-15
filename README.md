[![Build Status](https://dev.azure.com/michalczarnecki03/BookLab08/_apis/build/status%2FSkrytyZubr.docker-terraform-azure-pipeline?branchName=main)](https://dev.azure.com/michalczarnecki03/BookLab08/_build/latest?definitionId=6&branchName=main)

# Docker → ACR → ACI with Azure Pipelines and Terraform

This project demonstrates:
- Building a Docker image with a simple application (Apache httpd + `index.html`),
- Pushing the image to Azure Container Registry (ACR),
- Deploying it to Azure Container Instances (ACI) using Terraform,
- Using a remote Terraform backend stored in Azure Storage.

## High-Level CI/CD Architecture
```
Git push (main)
      │
Azure Pipelines (Docker@2)
  └─► Build image + Push → ACR (acrdemomc.azurecr.io)
      │
      └─► Terraform (azurerm)
              └─► RG: demoBook
              └─► ACI: aci-agent (dns: myapp-demomc)
                      └─► Container: myappdemo → port 80 (httpd)
```

## Repository Structure
```
.
├── Dockerfile                # Based on httpd:latest, copies index.html to /usr/local/apache2/htdocs/
├── index.html                # Simple test page served by Apache
├── azure-pipelines.yml       # Pipeline: Docker build&push + terraform init/apply
└── terraform-aci/
    ├── main.tf               # Provider, RG “demoBook”, ACI “aci-agent”, image from ACR, var.imageversion
    ├── versions.tf           # Provide versions of tools
    └── backend.tfvars        # Remote backend config (RG/SA/Container/Key)
```

## Deployed Resources
- **Resource Group**: `demoBook` (region: *West Europe*)
- **ACI (Container Group)**: `aci-agent` with public IP and `dns_name_label: myapp-demomc`
- **Container**: `myappdemo` from `acrdemomc.azurecr.io/demobook:${var.imageversion}` (default: `v1`)
- **Port**: 80/TCP

> After deployment, the app will be available at: `http://myapp-demomc.westeurope.azurecontainer.io/` (if the DNS label is unique in the region).

## Prerequisites
- **Azure**: subscription, ACR (or adjust naming in pipeline/TF), backend resources (Azure Storage) for Terraform.
- **Azure DevOps**: project + pipeline using `azure-pipelines.yml`.
- **Permissions**: Terraform Service Principal (ARM) + ACR connection in Azure Pipelines.
- **Optional local tools**: Azure CLI, Terraform, Docker.

## Remote Terraform Backend Configuration (Azure Storage)
`terraform-aci/backend.tfvars` example:
```
resource_group_name  = "MyRgRemoteBackend"
storage_account_name = "storageremotetfmc"
container_name       = "tfbackends"
key                  = "myapplidemopipeline.tfstate"
```
Create backend resources (once):
```bash
az group create -n MyRgRemoteBackend -l westeurope
az storage account create -g MyRgRemoteBackend -n storageremotetfmc -l westeurope --sku Standard_LRS
az storage container create --account-name storageremotetfmc -n tfbackends
```
Ensure `terraform { backend "azurerm" {} }` exists in your Terraform code.

## ACR Setup (demo)
```bash
az group create -n MyRgRemoteBackend -l westeurope
az acr create -g MyRgRemoteBackend -n acrdemomc --sku Basic
az acr update -n acrdemomc --admin-enabled true
az acr credential show -n acrdemomc  # get login/password for pipeline
```

## Azure Pipelines
File: `azure-pipelines.yml` (trigger on `main`).

### 1) Build Agent
Current config uses self‑hosted pool `wsl`:
```yaml
pool:
  name: wsl
```
If unavailable, replace with:
```yaml
pool:
  vmImage: 'ubuntu-latest'
```

### 2) Variables/Secrets
In **Variables** (mark sensitive where needed):
- `ARM_SUBSCRIPTION_ID`, `ARM_TENANT_ID`, `ARM_CLIENT_ID`, `ARM_CLIENT_SECRET` – for `azurerm` provider.
- `ARM_ACCESS_KEY` – Storage Account key for backend.
- `acr_username`, `acr_password` – ACR credentials.

Also set up a *Docker Registry Service Connection* for the `Docker@2` task.

### 3) Key YAML Parameters
```yaml
tag: 'v1'
```
`tag` should match `var.imageversion` in Terraform.

### 4) Pipeline Steps
1. **Build & Push** image to ACR (`demobook:v1`).
2. **Terraform init** in `terraform-aci/` with `backend.tfvars`.
3. **Terraform apply** – deploys RG `demoBook` + ACI `aci-agent` pulling image from ACR.

## Local Run (optional)
```bash
docker build -t acrdemomc.azurecr.io/demobook:v1 .
docker run -p 8080:80 acrdemomc.azurecr.io/demobook:v1
# open http://localhost:8080
```

## Terraform Variables
- `imageversion` – image tag (default `v1`).
- `acr_username`, `acr_password` – for `image_registry_credential`.

Example:
```hcl
image = "acrdemomc.azurecr.io/demobook:${var.imageversion}"
image_registry_credential {
  server   = "acrdemomc.azurecr.io"
  username = var.acr_username
  password = var.acr_password
}
```

## Accessing the App
After `apply`, ACI will have a public FQDN:
```
http://<your-acr>.westeurope.azurecontainer.io/
```

## Cleanup
From `terraform-aci/`:
```bash
terraform destroy -auto-approve
```
> This removes `demoBook` RG and its ACI. Backend resources remain.

## Common Issues
- **ACI stuck in “Waiting”**: check ACR credentials, image existence, and `imageversion`.
- **`terraform init` errors**: missing/misconfigured backend – verify `ARM_ACCESS_KEY` and `backend.tfvars`.
- **Missing `wsl` pool**: use `ubuntu-latest`.

## Best Practices
- Use **Managed Identity** with `AcrPull` role instead of ACR username/password.
- Store secrets in **Azure Key Vault** and retrieve in pipeline.
- Parameterize naming and regions.
- Add tags to resources and probes to the container.
