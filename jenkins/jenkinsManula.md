🚀 EC2 Jenkins Full Setup Commands (Ubuntu)
1. System update
sudo apt update && sudo apt upgrade -y
2. Install Git
sudo apt install -y git
3. Install Python + pip (for backend builds)
sudo apt install -y python3 python3-pip
4. Install Node.js + npm (for frontend builds)
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs
5. Install Docker prerequisites
sudo apt install -y ca-certificates curl gnupg lsb-release
6. Add Docker GPG key
sudo install -m 0755 -d /etc/apt/keyrings

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

sudo chmod a+r /etc/apt/keyrings/docker.gpg
7. Add Docker repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
8. Install Docker Engine + Compose
sudo apt update

sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
9. Start & enable Docker
sudo systemctl enable docker
sudo systemctl start docker
10. Add user to Docker group (VERY IMPORTANT for Jenkins)
sudo usermod -aG docker $USER
sudo usermod -aG docker jenkins

Apply group changes:

newgrp docker
11. Restart Jenkins (after Docker permission fix)
sudo systemctl restart jenkins

(Optional but recommended)

sudo reboot
12. Install AWS CLI v2
sudo apt install -y unzip curl

curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"

unzip awscliv2.zip

sudo ./aws/install
13. Verify everything
git --version
python3 --version
pip3 --version
node -v
npm -v
docker --version
docker compose version
aws --version