# Opsfleet Technical Assessment

This repository contains solutions for both tasks of the Opsfleet DevOps technical assessment.

## Repository Structure

```
├── terraform/      # Task 1: EKS + Karpenter Infrastructure
│   ├── bootstrap/  # State backend provisioning
│   ├── examples/   # Developer-facing K8s manifests (x86, ARM64, multi-arch, Spot)
│   ├── tests/      # Static and live validation test suites
│   ├── *.tf        # Terraform configuration files
│   └── README.md   # Detailed usage guide
│
└── architecture/   # Task 2: Cloud Architecture Design Document
    └── README.md   # Full architecture document with diagrams
```

## Task 1 — Technical

Production-grade Terraform code deploying:
- **EKS 1.36** cluster in a dedicated VPC with separate pod/node networking
- **Karpenter v1** with NodePools for both **x86 (amd64)** and **arm64 (Graviton)** instances
- **Spot** instances preferred for cost optimization with SQS interruption handling
- Full observability (CloudWatch alarms, VPC Flow Logs) and cost governance (AWS Budgets)

See [`terraform/README.md`](terraform/README.md) for usage instructions.

## Task 2 — Architecture

Architecture design document for "Innovate Inc." covering cloud environment structure, network design, EKS compute platform, CI/CD, PostgreSQL database, zero-trust security, observability, cost optimization, DR/HA, and scaling roadmap.

See [`architecture/README.md`](architecture/README.md) for the full document.
