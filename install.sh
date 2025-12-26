#!/bin/bash
# install-youtube-extractor.sh - Instalação completa do projeto

set -e

echo "🎵 YouTube Audio Extractor - Instalação Completa"
echo "=============================================="

# 1. Atualizar sistema
echo "1. Atualizando sistema..."
sudo apt update && sudo apt upgrade -y

# 2. Instalar Node.js via NVM (RECOMENDADO)
echo "2. Instalando Node.js via NVM..."
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash

# Carregar NVM no script atual
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# Instalar Node.js 18
nvm install 18
nvm use 18

# 3. Instalar dependências do sistema
echo "3. Instalando dependências do sistema..."
sudo apt install -y \
    git \
    curl \
    wget \
    ffmpeg \
    nginx \
    mariadb-server \
    mariadb-client \
    build-essential \
    python3 \
    python3-pip \
    unzip

# 4. Iniciar serviços
echo "4. Iniciando serviços..."
sudo systemctl start mariadb
sudo systemctl enable mariadb
sudo systemctl start nginx
sudo systemctl enable nginx

# 5. Clonar projeto
echo "5. Clonando projeto..."
cd /opt
sudo git clone https://github.com/Marcelo1408/youtube-audio-extractor.git
sudo chown -R $USER:$USER youtube-audio-extractor
cd youtube-audio-extractor

# 6. Instalar dependências Node.js
echo "6. Instalando dependências Node.js..."
npm install

# 7. Instalar PM2
echo "7. Instalando PM2..."
npm install -g pm2
pm2 startup

# 8. Configurar banco de dados
echo "8. Configurando banco de dados..."
sudo mysql -e "CREATE DATABASE IF NOT EXISTS youtube_extractor;"
sudo mysql -e "CREATE USER IF NOT EXISTS 'youtube_user'@'localhost' IDENTIFIED BY 'YoutubePass123!';"
sudo mysql -e "GRANT ALL PRIVILEGES ON youtube_extractor.* TO 'youtube_user'@'localhost';"
sudo mysql -e "FLUSH PRIVILEGES;"

# 9. Criar arquivo .env
echo "9. Criando arquivo de configuração..."
cp .env.example .env

# 10. Iniciar aplicação
echo "10. Iniciando aplicação..."
pm2 start server.js --name "youtube-extractor"
pm2 save

echo "✅ Instalação concluída!"
echo "🌐 Acesse: http://$(curl -s ifconfig.me)"
echo "📁 Diretório: /opt/youtube-audio-extractor"
