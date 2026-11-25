# 1. Aktuelles Ubuntu 24.04 AMI ermitteln

# Sucht das aktuellste verfügbare Ubuntu-24.04-Image.
data "aws_ami" "ubuntu" {
  most_recent = true

  # Filtert nach Ubuntu 24.04 für 64-Bit-Systeme.
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  # AWS-Konto-ID von Canonical (Ubuntu-Herausgeber).
  owners = ["099720109477"]
}


# 2. Standard-VPC ermitteln

# Liest die vorhandene Standard-VPC des AWS-Kontos aus.
data "aws_vpc" "default" {
  default = true
}


# 3. Security Group erstellen

# Erstellt eine virtuelle Firewall für die EC2-Instanz.
resource "aws_security_group" "allow_http" {
  name        = "allow_http"
  description = "Allow HTTP inbound traffic"

  # Verknüpft die Security Group mit der Standard-VPC.
  vpc_id = data.aws_vpc.default.id

  # Erlaubt eingehende HTTP-Verbindungen über Port 80
  # von allen IPv4-Adressen.
  ingress {
    description = "Allow HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Erlaubt sämtlichen ausgehenden Netzwerkverkehr.
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Vergibt einen Namen zur Identifikation in AWS.
  tags = {
    Name = "allow_http"
  }
}


# 4. EC2-Instanz erstellen

# Erstellt eine virtuelle Ubuntu-Maschine in AWS.
resource "aws_instance" "app_server" {

  # Verwendet das zuvor ermittelte Ubuntu-AMI.
  ami = data.aws_ami.ubuntu.id

  # Definiert den Instanztyp (1 vCPU, 1 GiB RAM).
  instance_type = "t2.micro"

  # Weist der Instanz die zuvor erstellte Security Group zu.
  vpc_security_group_ids = [aws_security_group.allow_http.id]

  # Weist automatisch eine öffentliche IP-Adresse zu.
  associate_public_ip_address = true

  # Führt beim ersten Start automatisch das Shell-Skript aus.
  # Installiert Apache und erstellt eine einfache Startseite.
  user_data = <<-EOF
    #!/bin/bash
    apt-get update
    apt-get install -y apache2
    systemctl start apache2
    systemctl enable apache2
    echo "<h1>Hello World</h1>" | tee /var/www/html/index.html
  EOF

  # Vergibt einen Namen zur Identifikation in AWS.
  tags = {
    Name = "learn-terraform"
  }
}


# 5. Öffentlichen DNS-Namen ausgeben

# Gibt den öffentlichen DNS-Namen der EC2-Instanz aus.
# Damit kann der Webserver über den Browser aufgerufen werden.
output "public_dns" {
  description = "Public DNS address of the EC2 instance"
  value       = aws_instance.app_server.public_dns
}
