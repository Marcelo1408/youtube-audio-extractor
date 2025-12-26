#!/bin/bash
# install-sql.sh - Database setup YouTube Audio Extractor
# Compatível com schema.sql fornecido

set -e

echo "=========================================="
echo "🗄️  CONFIGURAÇÃO DO BANCO DE DADOS"
echo "=========================================="

# ===============================
# CONFIGURAÇÕES
# ===============================
DB_NAME="youtube_audio_extractor"
DB_USER="youtube_audio_extractor_user"
DB_PASS="12Marcelo34#"
DB_HOST="localhost"
DB_PORT="3306"

read -p "📂 Informe o diretório do site (ex: /var/www/seusite.com): " PROJECT_DIR

if [ ! -d "$PROJECT_DIR" ]; then
  echo "❌ Diretório do site não encontrado"
  exit 1
fi

ENV_FILE="$PROJECT_DIR/.env"
SQL_DIR="$PROJECT_DIR/sql"
SCHEMA_FILE="$SQL_DIR/schema.sql"

# ===============================
# 1. Instalar MariaDB
# ===============================
if ! command -v mysql &> /dev/null; then
  echo "📦 Instalando MariaDB..."
  apt update -y
  apt install -y mariadb-server
  systemctl enable mariadb
  systemctl start mariadb
fi

# ===============================
# 2. Preparar diretório SQL
# ===============================
echo "📁 Preparando diretório sql..."
mkdir -p "$SQL_DIR"

if [ ! -f "$SCHEMA_FILE" ]; then
  echo "📥 Copiando schema.sql para o projeto..."
  curl -fsSL https://raw.githubusercontent.com/Marcelo1408/youtube-audio-extractor/main/schema.sql \
    -o "$SCHEMA_FILE"
fi

# ===============================
# 3. Criar banco e usuário
# ===============================
echo "📊 Criando banco e usuário..."

mysql <<EOF
CREATE DATABASE IF NOT EXISTS $DB_NAME
DEFAULT CHARACTER SET utf8mb4
DEFAULT COLLATE utf8mb4_unicode_ci;

CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;

USE $DB_NAME;
SOURCE $SCHEMA_FILE;
EOF

# ===============================
# 4. Atualizar .env (SEM SOBRESCREVER)
# ===============================
echo "⚙️  Configurando .env..."

if [ ! -f "$ENV_FILE" ]; then
  echo "📄 Criando .env..."
  cat > "$ENV_FILE" <<EOF
DB_HOST=$DB_HOST
DB_PORT=$DB_PORT
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASSWORD=$DB_PASS

PORT=3000
NODE_ENV=production
EOF
else
  echo "ℹ️  .env já existe — ajuste manual se necessário:"
  echo "DB_HOST=$DB_HOST"
  echo "DB_PORT=$DB_PORT"
  echo "DB_NAME=$DB_NAME"
  echo "DB_USER=$DB_USER"
  echo "DB_PASSWORD=$DB_PASS"
fi

# ===============================
# FINAL
# ===============================
echo ""
echo "=========================================="
echo "✅ BANCO CONFIGURADO COM SUCESSO!"
echo "=========================================="
echo "🌐 Banco: $DB_NAME"
echo "👤 Usuário DB: $DB_USER"
echo "🔑 Senha DB: $DB_PASS"
echo ""
echo "👑 ADMIN PADRÃO DO SISTEMA:"
echo "Email: admin@example.com"
echo "Senha: admin123"
echo ""
echo "📂 Projeto: $PROJECT_DIR"
echo "📁 SQL: $SQL_DIR/schema.sql"
echo "=========================================="
