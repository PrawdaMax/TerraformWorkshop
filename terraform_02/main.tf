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


# 2. VPC erstellen

# Erstellt ein eigenes virtuelles Netzwerk in AWS.
resource "aws_vpc" "my_vpc" {

  # Definiert den verfügbaren IP-Adressbereich der VPC.
  cidr_block = "10.0.0.0/16"

  # Aktiviert DNS-Auflösung und DNS-Hostnamen innerhalb der VPC.
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "my-vpc"
  }
}


# 3. Internet Gateway erstellen

# Ermöglicht der VPC die Kommunikation mit dem Internet.
resource "aws_internet_gateway" "my_igw" {

  # Verknüpft das Internet Gateway mit der erstellten VPC.
  vpc_id = aws_vpc.my_vpc.id

  tags = {
    Name = "my-igw"
  }
}


# 4. Eigene Routing-Tabelle erstellen

# Definiert, über welche Wege Netzwerkverkehr weitergeleitet wird.
resource "aws_route_table" "my_route_table" {
  vpc_id = aws_vpc.my_vpc.id

  # Leitet sämtlichen externen IPv4-Verkehr über
  # das Internet Gateway ins Internet.
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.my_igw.id
  }

  tags = {
    Name = "my-route-table"
  }
}


# 5. Subnetz erstellen

# Erstellt ein Subnetz innerhalb der VPC.
resource "aws_subnet" "my_subnet" {
  vpc_id     = aws_vpc.my_vpc.id
  cidr_block = "10.0.1.0/24"

  # Legt die Availability Zone fest, in der das Subnetz liegt.
  availability_zone = "us-east-1a"

  # Weist neuen Netzwerkressourcen automatisch öffentliche
  # IP-Adressen zu.
  map_public_ip_on_launch = true

  tags = {
    Name = "my-subnet"
  }
}


# 6. Subnetz mit Routing-Tabelle verbinden

# Weist dem Subnetz die zuvor erstellte Routing-Tabelle zu.
# Dadurch kann es über das Internet Gateway das Internet erreichen.
resource "aws_route_table_association" "my_route_table_association" {
  subnet_id      = aws_subnet.my_subnet.id
  route_table_id = aws_route_table.my_route_table.id
}


# 7. Security Group erstellen

# Erstellt eine virtuelle Firewall für die EC2-Instanz.
resource "aws_security_group" "my_security_group" {
  name        = "allow_http"
  description = "Allow HTTP inbound traffic"
  vpc_id      = aws_vpc.my_vpc.id

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

  tags = {
    Name = "allow_http"
  }
}


# 8. Netzwerkschnittstelle erstellen

# Erstellt eine virtuelle Netzwerkschnittstelle (ENI),
# über die die EC2-Instanz mit dem Netzwerk kommuniziert.
resource "aws_network_interface" "my_network_interface" {

  # Ordnet die Netzwerkschnittstelle dem Subnetz zu.
  subnet_id = aws_subnet.my_subnet.id

  # Weist eine feste private IP-Adresse zu.
  private_ips = ["10.0.1.50"]

  # Verknüpft die Netzwerkschnittstelle mit der Security Group.
  security_groups = [aws_security_group.my_security_group.id]

  tags = {
    Name = "my-network-interface"
  }
}


# 9. Elastic IP reservieren und zuweisen

# Reserviert eine statische öffentliche IPv4-Adresse,
# die dauerhaft der Netzwerkschnittstelle zugeordnet werden kann.
resource "aws_eip" "my_eip" {

  # Gibt an, dass die Elastic IP für eine VPC verwendet wird.
  domain = "vpc"

  # Verknüpft die Elastic IP mit der Netzwerkschnittstelle.
  network_interface = aws_network_interface.my_network_interface.id

  # Ordnet die Elastic IP der angegebenen privaten IP zu.
  associate_with_private_ip = "10.0.1.50"

  # Stellt sicher, dass Internet Gateway und EC2-Instanz
  # vor der Zuweisung der Elastic IP erstellt werden.
  depends_on = [
    aws_internet_gateway.my_igw,
    aws_instance.app_server
  ]

  tags = {
    Name = "my-elastic-ip"
  }
}


# 10. EC2-Instanz erstellen

# Erstellt eine virtuelle Ubuntu-Maschine in AWS.
resource "aws_instance" "app_server" {

  # Verwendet das zuvor ermittelte Ubuntu-AMI.
  ami = data.aws_ami.ubuntu.id

  # Definiert den Instanztyp (1 vCPU, 1 GiB RAM).
  instance_type = "t2.micro"

  # Verwendet die zuvor erstellte Netzwerkschnittstelle.
  network_interface {
    network_interface_id = aws_network_interface.my_network_interface.id

    # 0 bezeichnet die primäre Netzwerkschnittstelle.
    device_index = 0
  }

  # Installiert beim ersten Start Apache und erstellt
  # eine einfache HTML-Startseite.
  user_data = <<-EOF
    #!/bin/bash
    apt-get update
    apt-get install -y apache2
    systemctl start apache2
    systemctl enable apache2
    echo "<h1>Hello World</h1>" > /var/www/html/index.html
  EOF

  tags = {
    Name = "learn-terraform"
  }
}


# 11. Öffentliche IP-Adresse ausgeben

# Gibt die zugewiesene Elastic IP der EC2-Instanz aus.
# Über diese statische IP-Adresse kann der Webserver
# von außen erreicht werden.
output "public_ip" {
  description = "Public IP address of the EC2 instance"
  value       = aws_eip.my_eip.public_ip
}