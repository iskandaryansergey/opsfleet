################################################################################
# Karpenter IAM + SQS (via module)
################################################################################

module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 20.31"

  cluster_name = module.eks.cluster_name

  enable_v1_permissions           = true
  enable_pod_identity             = true
  create_pod_identity_association = true

  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }
}

################################################################################
# Karpenter Helm Release
################################################################################

resource "helm_release" "karpenter" {
  namespace = "kube-system"
  name      = "karpenter"

  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = var.karpenter_version
  wait       = true

  values = [yamlencode({
    settings = {
      clusterName       = module.eks.cluster_name
      clusterEndpoint   = module.eks.cluster_endpoint
      interruptionQueue = module.karpenter.queue_name
    }
    replicas = 2
    nodeSelector = {
      role = "system"
    }
    tolerations = [{
      key      = "CriticalAddonsOnly"
      operator = "Exists"
      effect   = "NoSchedule"
    }]
    topologySpreadConstraints = [{
      maxSkew           = 1
      topologyKey       = "topology.kubernetes.io/zone"
      whenUnsatisfiable = "ScheduleAnyway"
      labelSelector = {
        matchLabels = {
          "app.kubernetes.io/name" = "karpenter"
        }
      }
    }]
  })]

  depends_on = [module.karpenter, module.eks]
}

################################################################################
# EC2NodeClass
################################################################################

resource "kubectl_manifest" "karpenter_node_class" {
  yaml_body = yamlencode({
    apiVersion = "karpenter.k8s.aws/v1"
    kind       = "EC2NodeClass"
    metadata = {
      name = "default"
    }
    spec = {
      role = module.karpenter.node_iam_role_name
      amiSelectorTerms = [{
        alias = "al2023@latest"
      }]
      subnetSelectorTerms = [{
        tags = {
          "karpenter.sh/discovery" = local.name
        }
      }]
      securityGroupSelectorTerms = [{
        tags = {
          "karpenter.sh/discovery" = local.name
        }
      }]
      blockDeviceMappings = [{
        deviceName = "/dev/xvda"
        ebs = {
          volumeSize          = "50Gi"
          volumeType          = "gp3"
          iops                = 3000
          throughput          = 125
          encrypted           = true
          deleteOnTermination = true
        }
      }]
      metadataOptions = {
        httpEndpoint            = "enabled"
        httpProtocolIPv6        = "disabled"
        httpPutResponseHopLimit = 2
        httpTokens              = "required"
      }
      tags = {
        "karpenter.sh/discovery" = local.name
        ManagedBy                = "karpenter"
      }
    }
  })

  depends_on = [helm_release.karpenter]
}

################################################################################
# NodePools
################################################################################

resource "kubectl_manifest" "karpenter_nodepool_x86" {
  yaml_body = yamlencode({
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"
    metadata = {
      name = "x86-general"
    }
    spec = {
      template = {
        metadata = {
          labels = {
            arch = "amd64"
          }
        }
        spec = {
          expireAfter = "720h"
          nodeClassRef = {
            group = "karpenter.k8s.aws"
            kind  = "EC2NodeClass"
            name  = "default"
          }
          requirements = [
            { key = "kubernetes.io/arch", operator = "In", values = ["amd64"] },
            { key = "karpenter.sh/capacity-type", operator = "In", values = ["spot", "on-demand"] },
            { key = "node.kubernetes.io/instance-type", operator = "In", values = ["t3.small", "t3.micro", "c7i-flex.large", "m7i-flex.large"] },
          ]
        }
      }
      limits = {
        cpu    = "200"
        memory = "400Gi"
      }
      disruption = {
        consolidationPolicy = "WhenEmptyOrUnderutilized"
        consolidateAfter    = "30s"
        budgets             = [{ nodes = "20%" }]
      }
      weight = 40
    }
  })

  depends_on = [kubectl_manifest.karpenter_node_class]
}

resource "kubectl_manifest" "karpenter_nodepool_arm64" {
  yaml_body = yamlencode({
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"
    metadata = {
      name = "arm64-graviton"
    }
    spec = {
      template = {
        metadata = {
          labels = {
            arch = "arm64"
          }
        }
        spec = {
          expireAfter = "720h"
          nodeClassRef = {
            group = "karpenter.k8s.aws"
            kind  = "EC2NodeClass"
            name  = "default"
          }
          requirements = [
            { key = "kubernetes.io/arch", operator = "In", values = ["arm64"] },
            { key = "karpenter.sh/capacity-type", operator = "In", values = ["spot", "on-demand"] },
            { key = "node.kubernetes.io/instance-type", operator = "In", values = ["t4g.small", "t4g.micro"] },
          ]
        }
      }
      limits = {
        cpu    = "200"
        memory = "400Gi"
      }
      disruption = {
        consolidationPolicy = "WhenEmptyOrUnderutilized"
        consolidateAfter    = "30s"
        budgets             = [{ nodes = "20%" }]
      }
      weight = 60
    }
  })

  depends_on = [kubectl_manifest.karpenter_node_class]
}
