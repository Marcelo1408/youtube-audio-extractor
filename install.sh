#!/bin/bash
# YouTube Audio Extractor - Instalador Completo
# Ubuntu 20.04 / 22.04

set -e

clear
echo "=============================================="
echo "🚀 INSTALADOR YOUTUBE AUDIO EXTRACTOR"
echo "=============================================="
echo ""

# Verificar root
if [ "$EUID" -ne 0 ]; then
  echo "❌ Execute este script como root"
  exit 1
fi

# ===============================
# 1. Perguntas iniciais
# ===============================
read -p "🌐 Digite o domínio (ex: extractor.seudominio.com): " DOMAIN
read -p "📧 Digite o e-mail para SSL (Let's Encrypt): " EMAIL

if [ -z "$DOMAIN" ] || [ -z "$EMAIL" ]; then
  echo "❌ Domínio e e-mail são obrigatórios"
  exit 1
fi

WEB_DIR="/var/www/$DOMAIN"
ZIP_URL="https://github.com/Marcelo1408/youtube-audio-extractor/archive/refs/heads/main.zip"

# ===============================
# 2. Atualização do sistema
# ===============================
echo "📦 Atualizando sistema..."
apt update -y
apt upgrade -y

# ===============================
# 3. Instalar dependências
# ===============================
echo "📦 Instalando dependências..."
apt install -y \
  curl \
  unzip \
  git \
  nginx \
  ffmpeg \
  certbot \
  python3-certbot-nginx \
  ca-certificates \
  build-essential

# ===============================
# 4. Instalar Node.js 18 LTS
# ===============================
echo "🟢 Instalando Node.js 18..."
curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt install -y nodejs

# Verificação
if ! command -v npm &>/dev/null; then
  echo "❌ npm não foi instalado corretamente"
  exit 1
fi

# ===============================
# 5. Criar diretório do site
# ===============================
echo "📁 Criando diretório do site..."
mkdir -p "$WEB_DIR"
cd /tmp

# ===============================
# 6. Baixar e extrair site (ZIP)
# ===============================
echo "📥 Baixando source do GitHub..."
wget -O site.zip "$ZIP_URL"

echo "📦 Extraindo arquivos..."
unzip -o site.zip
cp -R youtube-audio-extractor-main/* "$WEB_DIR"

# ===============================
# 7. Instalar dependências Node
# ===============================
echo "📦 Instalando dependências do Node..."
cd "$WEB_DIR"
npm install --production

# ===============================
# 8. Permissões
# ===============================
echo "🔐 Ajustando permissões..."
chown -R www-data:www-data "$WEB_DIR"
chmod -R 755 "$WEB_DIR"

# ===============================
# 9. Configurar NGINX
# ===============================
echo "🌐 Configurando Nginx..."

cat > /etc/nginx/sites-available/$DOMAIN <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    root $WEB_DIR;
    index index.html index.js;

    location / {
        try_files \$uri \$uri/ /index.html;
    }

    location /api {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOF

ln -sf /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/
nginx -t
systemctl reload nginx

# ===============================
# 10. Ativar SSL
# ===============================
echo "🔒 Instalando SSL (Let's Encrypt)..."
certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "$EMAIL"

# ===============================
# FINAL
# ===============================
clear
echo "=============================================="
echo "🎉 SITE INSTALADO COM SUCESSO!"
echo "=============================================="
echo ""
echo "🌐 URL DO SITE:"
echo "https://$DOMAIN"
echo ""
echo "📂 Diretório:"
echo "$WEB_DIR"
echo ""
echo "🟢 Node.js: $(node -v)"
echo "📦 npm: $(npm -v)"
echo ""
echo "🔑 ADMIN:"
echo "➡️ Configure o usuário admin no arquivo de configuração do sistema"
echo "   (caso o projeto possua painel administrativo)"
echo ""
echo "✅ SSL ativo e Nginx configurado"
echo "=============================================="
