# DevOps Project 02 — AWS and Azure Deployments

Project này duy trì **hai phiên bản triển khai song song** cho cùng một website và cùng concept kiến trúc. Artifact AWS gốc được giữ nguyên; phiên bản Azure là một implementation bổ sung, không thay thế AWS.

## Chọn nền tảng

| Nền tảng | Tài liệu | Infrastructure artifacts |
|---|---|---|
| AWS | [AWS deployment guide](./VPC%20Architecture/README.md) | [`VPC Architecture/`](./VPC%20Architecture/) |
| Azure | [Azure deployment guide](./Azure%20Architecture/README.md) | [`Azure Architecture/`](./Azure%20Architecture/) |

Source website dùng chung: [`html-web-app/`](./html-web-app/).

## Concept chung

Cả hai phiên bản đều giữ cùng luồng triển khai:

```text
Golden machine image
→ Management/Bastion network tách biệt
→ Private application compute đa zone
→ Controlled outbound qua NAT
→ Public Layer 7 load balancer
→ Auto scaling từ 2 đến 4 instances
→ Object storage với least-privilege identity
→ DNS
→ Centralized logs, metrics và network flow logs
```

## Cấu trúc

```text
DevOps-Project-02/
├── README.md
├── VPC Architecture/          # Phiên bản AWS gốc
│   ├── README.md
│   ├── script.sh
│   ├── flow-logs.json
│   ├── flow-logs-trusted.json
│   ├── memory_metrics.json
│   └── s3-policy.json
├── Azure Architecture/        # Phiên bản Azure bổ sung
│   ├── README.md
│   ├── bootstrap.sh
│   ├── main.bicep
│   ├── flow-logs.bicep
│   ├── flow-logs.module.bicep
│   └── main.parameters.example.json
└── html-web-app/              # Website dùng chung
```

## Lưu ý

- Chạy AWS theo hướng dẫn trong `VPC Architecture/README.md`.
- Chạy Azure theo hướng dẫn trong `Azure Architecture/README.md`.
- Không chạy đồng thời hai stack nếu không cần thiết vì cả hai đều phát sinh chi phí cloud.
- Các policy và script trong `VPC Architecture` được giữ lại để triển khai, học tập và so sánh với Azure.
