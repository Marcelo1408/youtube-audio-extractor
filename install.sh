#!/bin/bash
# YouTube Audio Extractor - Instalador Completo
# Ubuntu 20.04 / 22.04

set -e

clear
echo "=============================================="
echo " INSTALADOR YOUTUBE AUDIO EXTRACTOR"
echo "=============================================="
echo ""

# ------------------------------------------------
# Verificar se é root
# ------------------------------------------------
if [ "$EUID" -ne 0 ]; then
  echo "❌ Execute este script como root"
  exit 1
fi

# ------------------------------------------------
# Perguntas iniciais
# ------------------------------------------------
read -p "🌐 Digite o domínio (ex: extractor.seudominio.com): " DOMAIN
read -p "📧 Digite o e-mail para SSL (Let's Encrypt): " EMAIL

if [ -z "$DOMAIN" ] || [ -z "$EMAIL" ]; then
  echo "❌ Domínio e e-mail são obrigatórios"
  exit 1
fi

WEB_DIR="/var/www/$DOMAIN"
TMP_DIR="/tmp/youtube-audio-extractor"

# ------------------------------------------------
# Atualização do sistema
# ------------------------------------------------
echo "📦 Atualizando sistema..."
apt update -y
apt upgrade -y

# ------------------------------------------------
# Instalar dependências
# ------------------------------------------------
echo "📦 Instalando dependências..."
apt install -y \
  curl \
  unzip \
  wget \
  git \
  nginx \
  ffmpeg \
  certbot \
  python3-certbot-nginx \
  ca-certificates \
  build-essential

# ------------------------------------------------
# Instalar Node.js 18 LTS
# ------------------------------------------------
echo "🟢 Instalando Node.js 18 LTS..."
curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt install -y nodejs

if ! command -v npm >/dev/null 2>&1; then
  echo "❌ npm não foi instalado corretamente"
  exit 1
fi

# ------------------------------------------------
# Preparar diretórios
# ------------------------------------------------
echo "📁 Preparando diretórios..."
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"
mkdir -p "$WEB_DIR"
cd /tmp

# ------------------------------------------------
# Baixar e extrair projeto
# ------------------------------------------------
echo "📥 Baixando projeto do GitHub..."
wget -O site.zip https://github.com/Marcelo1408/youtube-audio-extractor/archive/refs/heads/main.zip

echo "📦 Extraindo pacote principal..."
unzip -o site.zip -d "$TMP_DIR"

PROJECT_DIR="$TMP_DIR/youtube-audio-extractor-main"

echo "📦 Extraindo site real..."
cd "$PROJECT_DIR"
unzip -o youtube-audio-extractor.zip

# ------------------------------------------------
# Copiar arquivos do site (frontend + backend)
# ------------------------------------------------
echo "📁 Copiando arquivos do site para $WEB_DIR ..."
cp -R backend css js utils *.html *.txt .env package.json "$WEB_DIR"

# ------------------------------------------------
# Instalar dependências do Node.js
# ------------------------------------------------
echo "📦 Instalando dependências Node.js..."
cd "$WEB_DIR"
npm install --production

# ------------------------------------------------
# Permissões
# ------------------------------------------------
echo "🔐 Ajustando permissões..."
chown -R www-data:www-data "$WEB_DIR"
chmod -R 755 "$WEB_DIR"

# ------------------------------------------------
# Configurar Nginx
# ------------------------------------------------
echo "🌐 Configurando Nginx..."

cat > /etc/nginx/sites-available/$DOMAIN <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    root $WEB_DIR;
    index index.html;

    location / {
        try_files \$uri \$uri/ /index.html;
    }

    location /api {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOF

ln -sf /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/$DOMAIN

nginx -t
systemctl reload nginx

# ------------------------------------------------
# SSL com Let's Encrypt
# ------------------------------------------------
echo "🔒 Instalando SSL..."
certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "$EMAIL"

# ------------------------------------------------
# Finalização
# ------------------------------------------------
clear
echo "=============================================="
echo " SITE INSTALADO COM SUCESSO"
echo "=============================================="
echo ""
echo "🌐 URL:"
echo "https://$DOMAIN"
echo ""
echo "📂 Diretório:"
echo "$WEB_DIR"
echo ""
echo "🟢 Node.js: $(node -v)"
echo "📦 npm: $(npm -v)"
echo ""
echo "⚠️ IMPORTANTE:"
echo "- Execute o backend com PM2 ou systemd"
echo "- Banco de dados deve ser instalado ANTES (install-sql.sh)"
echo ""
echo "✅ Nginx e SSL configurados com sucesso"
echo "=============================================="
