#==============================================================================================================
# KUBERNETES RESOURCES - NAMESPACE
#==============================================================================================================
resource "kubernetes_namespace" "grafana" {
  count      = (var.enabled && var.create_namespace && var.namespace != "kube-system") ? 1 : 0

  metadata {
    name = var.namespace
  }
}
#==============================================================================================================
# HELM CHART - GRAFANA
#==============================================================================================================
locals {
  default_set_values = {
    "nodeSelector.kube/nodetype" = var.node_selector
  }
}

resource "helm_release" "grafana" {
  depends_on = [kubernetes_namespace.grafana]
  name             = "grafana"
  chart            = "grafana"
  repository       = "https://grafana.github.io/helm-charts"
  version          = "6.57.4"
  namespace        = var.create_namespace ? var.namespace : "grafana-system"

  dynamic "set" {
    for_each = try({ for key, value in local.default_set_values : key => value }, {})
    content {
      name  = set.key
      value = set.value
    }
  }

  values = [
    file("${path.module}/manifests/grafana.yaml")
  ]
}