data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_eks_cluster" "eks" {
  name = var.cluster_name
}

locals {
  account_id      = data.aws_caller_identity.current.account_id
  partition       = data.aws_partition.current.partition
  eks_oidc_issuer = trimprefix(data.aws_eks_cluster.eks.identity[0].oidc[0].issuer, "https://")
}
#==============================================================================================================
# IAM ROLE - KUBERNETES EBS CSI DRIVER
#==============================================================================================================
data "aws_iam_policy_document" "ebs_csi_data_assume_role" {
  count = var.enabled ? 1 : 0

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:oidc-provider/${local.eks_oidc_issuer}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.eks_oidc_issuer}:sub"

      values = [
        "system:serviceaccount:${var.namespace}:${var.service_account_name}",
      ]
    }
    effect = "Allow"
  }
}
data "aws_iam_policy_document" "ebs_csi_data_policy" {
  count = var.enabled ? 1 : 0
  statement {
    actions = [
      "route53:GetChange"
    ]
    resources = [
      "arn:aws:route53:::change/*"
    ]
    effect = "Allow"
  }
  statement {
    actions = [
      "route53:ChangeResourceRecordSets",
      "route53:ListResourceRecordSets"
    ]
    resources = [
      "arn:aws:route53:::hostedzone/*"
    ]
    effect = "Allow"
  }
  statement {
    actions = [
      "route53:ListHostedZonesByName"
    ]
    resources = [
      "*"
    ]
    effect = "Allow"
  }
}
resource "aws_iam_policy" "ebs_csi_policy" {
  count       = var.enabled ? 1 : 0
  name        = "${var.cluster_name}-ebs-csi-driver-policy"
  path        = "/"
  description = "Policy for cert-manager service"

  policy = data.aws_iam_policy_document.ebs_csi_data_policy[0].json
}
resource "aws_iam_role" "ebs_csi_role" {
  count              = var.enabled ? 1 : 0
  name               = "${var.cluster_name}-ebs-csi-driver"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_data_assume_role[0].json
}
resource "aws_iam_role_policy_attachment" "kubernetes_cert_manager" {
  count      = var.enabled ? 1 : 0
  role       = aws_iam_role.ebs_csi_role[0].name
  policy_arn = aws_iam_policy.ebs_csi_policy[0].arn
}
#==============================================================================================================
# KUBERNETES RESOURCES - NAMESPACE
#==============================================================================================================
resource "kubernetes_namespace_v1" "ebs_csi_driver" {
  count = (var.enabled && var.create_namespace && var.namespace != "default") ? 1 : 0

  metadata {
    name = var.namespace
  }
}
#==============================================================================================================
# HELM RELEASE - EBS CSI DRIVER
#==============================================================================================================
resource "helm_release" "aws_ebs_csi_driver" {
  depends_on = [kubernetes_namespace_v1.ebs_csi_driver]
  name             = var.helm_chart_name
  repository       = var.helm_chart_repo
  chart            = var.helm_chart_name
  version          = var.helm_chart_version
  force_update     = false
  namespace        = var.create_namespace ? var.namespace : "kube-system"

  set {
    name  = "controller.serviceAccount.create"
    value = "true"
    type  = "auto"
  }

  set {
    name  = "controller.serviceAccount.name"
    value = "aws-ebs-csi-driver"
    type  = "auto"
  }

  set {
    name  = "controller.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.ebs_csi_role[0].arn
    type  = "auto"
  }
}
