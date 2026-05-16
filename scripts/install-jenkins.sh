#!/bin/bash
set -e

echo "==> Updating packages"
apt-get update -y
apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release unzip fontconfig openjdk-17-jdk

echo "==> Installing Jenkins"
curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key \
    | tee /usr/share/keyrings/jenkins-keyring.asc > /dev/null
echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] \
    https://pkg.jenkins.io/debian-stable binary/" \
    | tee /etc/apt/sources.list.d/jenkins.list > /dev/null
apt-get update -y
apt-get install -y jenkins
systemctl enable --now jenkins

echo "==> Installing Docker"
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
    https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io
systemctl enable --now docker

echo "==> Adding jenkins user to docker group"
usermod -aG docker jenkins
systemctl restart jenkins

echo "==> Installing AWS CLI v2"
curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscli.zip
unzip -q /tmp/awscli.zip -d /tmp
/tmp/aws/install
rm -rf /tmp/awscli.zip /tmp/aws

echo "==> Installing Python 3 and Node.js"
apt-get install -y python3 python3-pip nodejs npm

PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
echo ""
echo "==> Done! Jenkins is running."
echo "    URL:              http://${PUBLIC_IP}:8080"
echo "    Unlock password:  sudo cat /var/lib/jenkins/secrets/initialAdminPassword"
