#!/bin/bash
# YouTube Audio Extractor - Instalador Estável
# Ubuntu 20.04 / 22.04
# Node.js 18 LTS

set -e

echo "========================================="
echo "🚀 Instalador YouTube Audio Extractor"
echo "========================================="

# Garantir execução como root
if [ "$EUID" -ne 0 ]; then
  echo "❌ Execute como root"
  exit 1
fi

# Diretório do projeto
PROJECT_DIR="/opt/youtube-audio-extractor"

# ===============================
# 1. Limpeza básica (segura)
# ===============================
echo "🧹 Limpando instalações antigas..."
apt remove --purge -y nodejs npm || true
apt autoremove -y
rm -rf /usr/local/lib/node_modules
rm -rf ~/.npm

# ===============================
# 2. Dependências básicas
# ===============================
echo "📦 Instalando dependências..."
apt update -y
apt install -y curl git ca-certificates build-essential

# ===============================
# 3. Instalar Node.js 18 LTS (FORMA CORRETA)
# ===============================
echo "🟢 Instalando Node.js 18 LTS..."

curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt install -y nodejs

# ===============================
# 4. Verificação REAL
# ===============================
echo "🔍 Verificando Node e npm..."

NODE_PATH=$(which node || true)
NPM_PATH=$(which npm || true)

if [ -z "$NODE_PATH" ] || [ -z "$NPM_PATH" ]; then
  echo "❌ Node.js ou npm não foram instalados corretamente"
  exit 1
fi

echo "✅ Node: $NODE_PATH ($(node -v))"
echo "✅ npm: $NPM_PATH ($(npm -v))"

# ===============================
# 5. Clonar ou atualizar projeto
# ===============================
echo "📁 Instalando projeto..."

if [ ! -d "$PROJECT_DIR/.git" ]; then
  git clone https://github.com/Marcelo1408/youtube-audio-extractor.git "$PROJECT_DIR"
else
  cd "$PROJECT_DIR"
  git pull origin main
fi

cd "$PROJECT_DIR"

# ===============================
# 6. Instalar dependências do projeto
# ===============================
echo "📦 Instalando dependências npm..."
npm install --production

# ===============================
# 7. Permissões
# ===============================
echo "🔐 Ajustando permissões..."
chown -R root:root "$PROJECT_DIR"
chmod -R 755 "$PROJECT_DIR"

# ===============================
# FINAL
# ===============================
echo ""
echo "========================================="
echo "🎉 INSTALAÇÃO CONCLUÍDA COM SUCESSO"
echo "========================================="
echo "📂 Projeto: $PROJECT_DIR"
echo "🟢 Node: $(node -v)"
echo "📦 npm: $(npm -v)"
