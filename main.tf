#####################################
#     VPC Creation
#####################################
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "trade-bot-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["eu-south-2a", "eu-south-2b"]
  private_subnets = ["10.0.0.0/18", "10.0.64.0/18"]
  public_subnets  = ["10.0.128.0/18", "10.0.192.0/18"]

  enable_nat_gateway = false
  enable_vpn_gateway     = false
  one_nat_gateway_per_az = false

  enable_dns_hostnames = true

  tags = {
    Terraform   = "true"
    Environment = terraform.workspace
  }
}


##########################################
#  EC2 SSH access
##########################################
resource "aws_security_group" "ec2-ssh-sg" {
  vpc_id = module.vpc.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_iam_role" "ec2_ssm_role" {
  name = "trade-ec2-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_policy" {
  role       = aws_iam_role.ec2_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_ssm_profile" {
  name = "ec2-ssm-profile"
  role = aws_iam_role.ec2_ssm_role.name
}

##########################################
#  5002, 5005 - Access on Internet
##########################################
resource "aws_security_group" "ec2-services-access-sg" {
  vpc_id = module.vpc.vpc_id

  ingress {
    from_port   = 5002
    to_port     = 5002
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 5005
    to_port     = 5005
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


#######################################
# EC2 server creation
#######################################
module "ec2_instance" {
  source = "terraform-aws-modules/ec2-instance/aws"

  name = "trade-bot-instance"
  ami  = "ami-01bfa473cd77d6efc"
  instance_type = "t3.small"
  
  # Security group and subnet
  vpc_security_group_ids = [aws_security_group.ec2-ssh-sg.id, aws_security_group.ec2-services-access-sg.id]
  subnet_id              = module.vpc.public_subnets[0]

  # IAM Role for SSM
  iam_instance_profile = aws_iam_instance_profile.ec2_ssm_profile.name
  associate_public_ip_address = true

  # Root volume configuration (Set size to 30GB)
  root_block_device = [{
    volume_size           = 30
    volume_type           = "gp3"
    delete_on_termination = true
  }]

# User Data Script
 user_data = <<-EOF
          #!/bin/bash
          sudo apt update -y

          # Install Amazon SSM Agent
          wget https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/debian_amd64/amazon-ssm-agent.deb
          sudo dpkg -i amazon-ssm-agent.deb
          sudo systemctl enable amazon-ssm-agent
          sudo systemctl start amazon-ssm-agent

          # Install required dependencies
          sudo apt install -y apt-transport-https ca-certificates curl software-properties-common git vim

          # Install Docker
          curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
          echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
          sudo apt update -y
          sudo apt install -y docker-ce docker-ce-cli containerd.io

          # Start Docker & enable it on boot
          sudo systemctl start docker
          sudo systemctl enable docker

          # Add 'ssm-user' to the docker group to run without sudo
          sudo usermod -aG docker ssm-user

          # Install Docker Compose
          sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
          sudo chmod +x /usr/local/bin/docker-compose

          # Verify installations
          docker --version
          docker-compose --version
  EOF

  tags = {
    Terraform   = "true"
    Environment = terraform.workspace
  }
}
