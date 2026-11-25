# 0. Variablen

# Anzahl der Webserver-Instanzen hinter dem Load Balancer.
variable "instance_count" {
  description = "Number of EC2 instances behind the load balancer"
  type        = number
  default     = 2
}

# Availability Zones für die Subnetze.
# Ein Application Load Balancer benötigt mindestens zwei Subnetze
# in unterschiedlichen Availability Zones.
variable "availability_zones" {
  description = "Availability zones for the subnets (at least two)"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}


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


# 2. VPC erstellen (aus Workshop 2)

# Erstellt ein eigenes virtuelles Netzwerk in AWS.
resource "aws_vpc" "my_vpc" {
  cidr_block = "10.0.0.0/16"

  # Aktiviert DNS-Auflösung und DNS-Hostnamen innerhalb der VPC.
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "my-vpc"
  }
}


# 3. Internet Gateway erstellen

# Verbindet die VPC mit dem Internet.
resource "aws_internet_gateway" "my_igw" {
  vpc_id = aws_vpc.my_vpc.id

  tags = {
    Name = "my-igw"
  }
}


# 4. Routing-Tabelle erstellen

# Leitet sämtlichen externen IPv4-Verkehr über das Internet Gateway.
resource "aws_route_table" "my_route_table" {
  vpc_id = aws_vpc.my_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.my_igw.id
  }

  tags = {
    Name = "my-route-table"
  }
}


# 5. Subnetze erstellen (eines pro Availability Zone)

# Mit "count" wird für jede Availability Zone ein Subnetz erzeugt:
# 10.0.1.0/24 in us-east-1a, 10.0.2.0/24 in us-east-1b.
resource "aws_subnet" "my_subnet" {
  count = length(var.availability_zones)

  vpc_id            = aws_vpc.my_vpc.id
  cidr_block        = "10.0.${count.index + 1}.0/24"
  availability_zone = var.availability_zones[count.index]

  # Instanzen erhalten eine öffentliche IP, damit sie beim Start
  # Pakete (Apache) aus dem Internet laden können.
  map_public_ip_on_launch = true

  tags = {
    Name = "my-subnet-${count.index + 1}"
  }
}


# 6. Subnetze mit Routing-Tabelle verbinden

resource "aws_route_table_association" "my_route_table_association" {
  count = length(aws_subnet.my_subnet)

  subnet_id      = aws_subnet.my_subnet[count.index].id
  route_table_id = aws_route_table.my_route_table.id
}


# 7. Security Group für den Load Balancer

# Erlaubt HTTP-Zugriff aus dem gesamten Internet auf den Load Balancer.
resource "aws_security_group" "lb_sg" {
  name        = "lb_allow_http"
  description = "Allow HTTP inbound traffic to the load balancer"
  vpc_id      = aws_vpc.my_vpc.id

  ingress {
    description = "Allow HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "lb_allow_http"
  }
}


# 8. Security Group für die Webserver

# Erlaubt HTTP nur vom Load Balancer, nicht direkt aus dem Internet.
# Dadurch ist der Load Balancer der einzige Zugangspunkt.
resource "aws_security_group" "web_sg" {
  name        = "web_allow_http_from_lb"
  description = "Allow HTTP inbound traffic only from the load balancer"
  vpc_id      = aws_vpc.my_vpc.id

  ingress {
    description     = "Allow HTTP from the load balancer"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.lb_sg.id]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "web_allow_http_from_lb"
  }
}


# 9. Mehrere EC2-Instanzen erstellen

# "count" erzeugt var.instance_count Instanzen (Standard: 2).
# Die Instanzen werden abwechselnd auf die Subnetze verteilt,
# sodass sie in unterschiedlichen Availability Zones laufen.
resource "aws_instance" "app_server" {
  count = var.instance_count

  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.my_subnet[count.index % length(aws_subnet.my_subnet)].id
  vpc_security_group_ids = [aws_security_group.web_sg.id]

  # Installiert Apache und erstellt eine Startseite, die anzeigt,
  # welche Instanz antwortet. So sieht man beim Neuladen im Browser,
  # dass der Load Balancer zwischen den Instanzen wechselt.
  user_data = <<-EOF
    #!/bin/bash
    apt-get update
    apt-get install -y apache2
    systemctl start apache2
    systemctl enable apache2
    echo "<h1>Hello World from server ${count.index + 1}</h1><p>Host: $(hostname)</p>" > /var/www/html/index.html
  EOF

  tags = {
    Name = "learn-terraform-${count.index + 1}"
  }
}


# 10. Application Load Balancer erstellen

# Öffentlich erreichbarer Load Balancer über beide Subnetze.
resource "aws_lb" "my_lb" {
  name               = "my-load-balancer"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.lb_sg.id]
  subnets            = aws_subnet.my_subnet[*].id

  tags = {
    Name = "my-load-balancer"
  }
}


# 11. Target Group erstellen

# Gruppe von Zielen (Instanzen), an die der Load Balancer weiterleitet.
# Der Health Check prüft regelmäßig, ob die Webserver antworten.
resource "aws_lb_target_group" "my_target_group" {
  name     = "my-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.my_vpc.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = {
    Name = "my-target-group"
  }
}


# 12. Instanzen in der Target Group registrieren

# Verknüpft jede erstellte Instanz mit der Target Group.
resource "aws_lb_target_group_attachment" "my_attachment" {
  count = var.instance_count

  target_group_arn = aws_lb_target_group.my_target_group.arn
  target_id        = aws_instance.app_server[count.index].id
  port             = 80
}


# 13. Listener erstellen

# Nimmt HTTP-Anfragen auf Port 80 entgegen und leitet sie
# an die Target Group (also an die Instanzen) weiter.
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.my_lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.my_target_group.arn
  }
}


# 14. Ausgaben

# DNS-Adresse des Load Balancers – über diese Adresse
# ist die Anwendung im Browser erreichbar.
output "load_balancer_dns" {
  description = "DNS address of the load balancer"
  value       = aws_lb.my_lb.dns_name
}

# IDs der erstellten Instanzen (zur Kontrolle).
output "instance_ids" {
  description = "IDs of the EC2 instances behind the load balancer"
  value       = aws_instance.app_server[*].id
}
