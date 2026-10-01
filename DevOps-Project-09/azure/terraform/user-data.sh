#!/bin/bash
set -e

# Cập nhật hệ thống
apt-get update -y
apt-get upgrade -y

# Cài đặt các gói phụ trợ
apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release git jq

# Cài đặt Docker Official GPG Key & Repository
mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Cấu hình vm.max_map_count cho SonarQube (bắt buộc)
sysctl -w vm.max_map_count=262144
echo "vm.max_map_count=262144" >> /etc/sysctl.conf
sysctl -w fs.file-max=65536
echo "fs.file-max=65536" >> /etc/sysctl.conf

# Cho phép user không phải root chạy Docker và truy cập socket
usermod -aG docker azureuser || true
chmod 666 /var/run/docker.sock || true

# Tạo thư mục làm việc cho stack DevSecOps
mkdir -p /opt/devops-stack
chown -R azureuser:azureuser /opt/devops-stack

echo "=== VM Initialization and Docker setup complete ===" > /var/log/user-data-complete.log
