variable "ec2-setup" {
  default = <<EOF
#!/bin/bash
sudo dnf -y update
sudo dnf -y localinstall https://dev.mysql.com/get/mysql80-community-release-el9-1.noarch.rpm
sudo dnf -y install mysql mysql-community-client
sudo dnf install -y nginx
sudo dnf list | grep php
sudo dnf install -y wget php-fpm php-mysqli php-json php php-devel php-gd
sudo systemctl start php-fpm
sudo systemctl start nginx
sudo systemctl enable nginx php-fpm
  EOF
}
