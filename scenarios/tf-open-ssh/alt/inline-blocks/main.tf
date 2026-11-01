resource "aws_vpc" "edge" {
  cidr_block = "10.50.0.0/16"
}

# Same intent as the reference fix, written with inline blocks.
resource "aws_security_group" "web" {
  name_prefix = "web-"
  vpc_id      = aws_vpc.edge.id

  ingress {
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    description = "SSH from office"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["198.51.100.0/24"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
