############################
# Networking
############################
module "networking" {
  source = "./modules/networking"

  project_name = var.project_name
  tags         = var.tags
}

############################
# EKS Cluster
############################
module "eks" {
  source = "./modules/eks"

  project_name      = var.project_name
  subnet_ids        = module.networking.private_subnet_ids
  security_group_id = module.networking.eks_nodes_sg_id
  lab_role_arn      = var.lab_role_arn
  tags              = var.tags
}

############################
# Databases (RDS, Redis, DynamoDB)
############################
module "databases" {
  source = "./modules/databases"

  project_name       = var.project_name
  vpc_id             = module.networking.vpc_id
  private_subnet_ids = module.networking.private_subnet_ids
  rds_sg_id          = module.networking.rds_sg_id
  redis_sg_id        = module.networking.redis_sg_id
  db_password        = var.db_password
  tags               = var.tags
}

############################
# Messaging (SQS)
############################
module "messaging" {
  source = "./modules/messaging"

  project_name = var.project_name
  tags         = var.tags
}

############################
# ECR Repositories
############################
module "ecr" {
  source = "./modules/ecr"

  tags = var.tags
}

############################
# SG Rules: EKS cluster SG -> RDS/Redis
# (EKS cria um SG proprio que os nodes usam,
#  precisamos permitir esse SG nos SGs de RDS e Redis)
############################
resource "aws_security_group_rule" "rds_from_eks_cluster_sg" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = module.eks.cluster_security_group_id
  security_group_id        = module.networking.rds_sg_id
  description              = "PostgreSQL from EKS cluster SG"
}

resource "aws_security_group_rule" "redis_from_eks_cluster_sg" {
  type                     = "ingress"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  source_security_group_id = module.eks.cluster_security_group_id
  security_group_id        = module.networking.redis_sg_id
  description              = "Redis from EKS cluster SG"
}
