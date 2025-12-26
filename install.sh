# Corrigir npm manualmente
sudo apt purge nodejs npm -y
sudo apt autoremove -y
sudo apt update
sudo apt install -y curl
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt install -y nodejs
node --version
npm --version

# Se npm ainda não funcionar
curl -L https://www.npmjs.com/install.sh | sudo sh
