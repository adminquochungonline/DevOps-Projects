# 🚀 Kiến Trúc Triển Khai Hybrid: Local Docker (CI) ➔ Azure Managed Services (CD)

> **Mô hình Tinh gọn (Cost-Optimized & Production-Ready):**
> Toàn bộ các công cụ CI/CD (**Jenkins, SonarQube, Ansible**) đã được dựng sẵn dưới dạng **Docker Containers tại Local**. Vì vậy, **hoàn toàn KHÔNG cần tạo các máy ảo (VM) tốn kém trên Azure**. 
> Phía Azure Cloud chỉ cần khởi tạo 2 dịch vụ Managed: **Azure Container Registry (ACR)** và **Azure Kubernetes Service (AKS)**.

---

## 🏗️ Kiến Trúc Hệ Thống (Hybrid CI/CD)

```text
┌─────────────────────────────────────────────────────────────┐
│                      MÔI TRƯỜNG LOCAL                       │
│                                                             │
│  [ Developer ] ──► Commit code                              │
│         │                                                   │
│         ▼                                                   │
│  [ dp01-jenkins (Docker) ]                                  │
│         ├─► [ Maven Build & Unit Test ]                     │
│         ├─► [ dp01-sonarqube ] (Code Analysis & QG)         │
│         ├─► [ Docker Build ] (Đóng gói Image)               │
│         │                                                   │
└─────────┼───────────────────────────────────────────────────┘
          │
          │ (Đẩy Image & Deploy qua Internet)
          ▼
┌─────────────────────────────────────────────────────────────┐
│                    MICROSOFT AZURE CLOUD                    │
│                                                             │
│  [ Azure Container Registry (ACR) ]                         │
│         │                                                   │
│         │ (Kéo Image qua vai trò AcrPull)                   │
│         ▼                                                   │
│  [ Azure Kubernetes Service (AKS) ]                         │
│         ├─► sample-app (Deployment / Pods)                  │
│         └─► Azure Load Balancer (Public IP truy cập app)    │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## ⚡ Các Bước Thực Hiện Đã Được Rút Gọn

Nhờ các công cụ đã có sẵn ở Local:
- ❌ **BỎ QUA**: Step 1 (Tạo 3 Azure VMs), Step 2 (SSH Passwordless giữa các VM), Step 3 (Ansible Playbooks cài Jenkins lên VM), Step 4 (Master-Agent VM).
- ✅ **CHỈ CẦN THỰC HIỆN**:

### 1️⃣ Khởi tạo ACR và AKS bằng Terraform (Trên Azure)
Chỉ mất khoảng 4-5 phút để khởi tạo cụm Kubernetes và Registry:
```bash
cd azure/terraform/aks
terraform init
terraform plan
terraform apply -auto-approve
```
* **Kết quả**:
  * Tạo cụm **AKS** (`aks-devops-project-06`).
  * Tạo **ACR** (`acrdevops06app.azurecr.io`).
  * Tự động liên kết quyền `AcrPull` để AKS tự động kéo image từ ACR mà không cần bí mật docker-registry secret.

### 2️⃣ Tạo Service Principal trên Azure để Jenkins xác thực
Tạo Service Principal để cấp quyền cho Local Jenkins deploy lên AKS và push lên ACR:
```bash
az ad sp create-for-rbac \
  --name "sp-jenkins-local" \
  --role "Contributor" \
  --scopes /subscriptions/<SUBSCRIPTION_ID>/resourceGroups/rg-devops-project-06
```
Lưu lại `appId` (Client ID), `password` (Client Secret) và `tenant` (Tenant ID).

### 3️⃣ Cấu hình Credentials trên Local Jenkins
Truy cập Jenkins tại `http://localhost:8080`:
1. **Azure Service Principal (`azure-sp-credentials`)**:
   - Loại: *Azure Service Principal* (hoặc Secret Text).
2. **ACR Credentials (`azure-acr-credentials`)**:
   - Loại: *Username with password* (Username: tên ACR hoặc Service Principal appId; Password: ACR admin key hoặc secret).
3. **SonarQube Token**:
   - Cấu hình server SonarQube trỏ tới: `http://sonarqube:9000` (kết nối nội bộ mạng Docker `dp01-cicd`).

### 4️⃣ Chạy Pipeline từ Jenkinsfile
* Tạo Pipeline Job trỏ vào file [azure/Jenkinsfile](file:///home/adminhung/DevOps-Projects/DevOps-Project-06/azure/Jenkinsfile).
* Jenkins local sẽ tự động:
  1. Compile mã nguồn Java bằng Maven.
  2. Quét chất lượng code qua SonarQube container local (`dp01-sonarqube:9000`).
  3. Build Docker container image.
  4. Đăng nhập và đẩy image lên Azure ACR.
  5. Kết nối tới AKS (`az aks get-credentials`) và áp dụng các file manifests trong [azure/k8s/](file:///home/adminhung/DevOps-Projects/DevOps-Project-06/azure/k8s).

### 5️⃣ Truy cập Ứng dụng
Sau khi deployment hoàn tất, lấy Public IP do Azure Load Balancer cấp:
```bash
az aks get-credentials --resource-group rg-devops-project-06 --name aks-devops-project-06
kubectl get svc sample-app-svc -n sample-app
```
Truy cập: `http://<EXTERNAL-IP>`
