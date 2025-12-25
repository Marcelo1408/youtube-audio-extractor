#!/bin/bash
# backend/database/install.sh - Script de instalação do banco de dados

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; }

# Banner
echo -e "${BLUE}"
cat << "EOF"
╔══════════════════════════════════════════════╗
║   YouTube Audio Extractor - Database Setup   ║
╚══════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Verificar se MariaDB/MySQL está instalado
if ! command -v mysql &> /dev/null; then
    error "MariaDB/MySQL não está instalado."
    echo "Para instalar:"
    echo "  Ubuntu/Debian: sudo apt install mariadb-server"
    echo "  CentOS/RHEL: sudo yum install mariadb-server"
    echo "  Após instalar: sudo systemctl start mariadb && sudo systemctl enable mariadb"
    exit 1
fi

# Verificar se o serviço está rodando
if ! systemctl is-active --quiet mariadb 2>/dev/null && ! systemctl is-active --quiet mysql 2>/dev/null; then
    warn "Serviço MySQL/MariaDB não está rodando."
    read -p "Tentar iniciar o serviço? (s/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Ss]$ ]]; then
        sudo systemctl start mariadb 2>/dev/null || sudo systemctl start mysql 2>/dev/null
        sleep 3
    else
        error "Serviço do banco de dados não está disponível."
        exit 1
    fi
fi

# Obter credenciais
echo "🔐 Configuração do banco de dados"
echo "---------------------------------"

# Tentar autenticação sem senha primeiro
CAN_CONNECT=false
if mysql -u root -e "SELECT 1" &>/dev/null; then
    DB_USER="root"
    DB_PASS=""
    CAN_CONNECT=true
    log "Conectado como root (sem senha)"
fi

if [ "$CAN_CONNECT" = false ]; then
    # Solicitar credenciais
    while true; do
        read -p "Usuário MySQL (padrão: root): " DB_USER
        DB_USER=${DB_USER:-root}
        
        echo -n "Senha MySQL: "
        read -s DB_PASS
        echo ""
        
        # Testar conexão
        if mysql -u "$DB_USER" -p"$DB_PASS" -e "SELECT 1" &>/dev/null; then
            log "Conexão bem-sucedida!"
            CAN_CONNECT=true
            break
        else
            error "Falha na conexão. Verifique usuário/senha."
            read -p "Tentar novamente? (s/n): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Ss]$ ]]; then
                exit 1
            fi
        fi
    done
fi

# Configurações adicionais
read -p "Host MySQL (padrão: localhost): " DB_HOST
DB_HOST=${DB_HOST:-localhost}

read -p "Porta MySQL (padrão: 3306): " DB_PORT
DB_PORT=${DB_PORT:-3306}

read -p "Nome do banco (padrão: youtube_audio_extractor): " DB_NAME
DB_NAME=${DB_NAME:-youtube_audio_extractor}

# Perguntar sobre usuário específico para aplicação
echo ""
echo "👤 Usuário da aplicação"
echo "---------------------------------"
read -p "Criar usuário específico para a aplicação? (s/n): " -n 1 -r
echo
CREATE_APP_USER=false
if [[ $REPLY =~ ^[Ss]$ ]]; then
    CREATE_APP_USER=true
    read -p "Nome do usuário da aplicação (padrão: yt_extractor_user): " APP_USER
    APP_USER=${APP_USER:-yt_extractor_user}
    
    while true; do
        echo -n "Senha para o usuário da aplicação: "
        read -s APP_PASS
        echo ""
        
        if [ -z "$APP_PASS" ]; then
            warn "Senha não pode ser vazia!"
            continue
        fi
        
        echo -n "Confirmar senha: "
        read -s APP_PASS_CONFIRM
        echo ""
        
        if [ "$APP_PASS" != "$APP_PASS_CONFIRM" ]; then
            error "Senhas não coincidem!"
        else
            break
        fi
    done
fi

# Caminho do schema
SCHEMA_FILE="$(dirname "$0")/schema.sql"
if [ ! -f "$SCHEMA_FILE" ]; then
    SCHEMA_FILE="./schema.sql"
fi

if [ ! -f "$SCHEMA_FILE" ]; then
    error "Arquivo schema.sql não encontrado!"
    echo "Certifique-se de que schema.sql está no mesmo diretório."
    exit 1
fi

# Criar banco de dados
echo ""
echo "📊 Criando banco de dados..."
echo "---------------------------------"

# Executar comandos SQL
SQL_COMMANDS="
-- Criar banco de dados
CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

USE \`$DB_NAME\`;
"

# Adicionar schema
SQL_COMMANDS+=$(cat "$SCHEMA_FILE")

# Adicionar usuário da aplicação se solicitado
if [ "$CREATE_APP_USER" = true ]; then
    SQL_COMMANDS+="
-- Criar usuário para a aplicação
CREATE USER IF NOT EXISTS '$APP_USER'@'$DB_HOST' IDENTIFIED BY '$APP_PASS';

-- Conceder permissões
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$APP_USER'@'$DB_HOST';

-- Atualizar privilégios
FLUSH PRIVILEGES;
"
fi

# Executar SQL
if [ -z "$DB_PASS" ]; then
    mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -e "$SQL_COMMANDS"
else
    mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASS" -e "$SQL_COMMANDS"
fi

if [ $? -eq 0 ]; then
    log "✅ Banco de dados criado com sucesso!"
    
    # Verificar tabelas criadas
    echo ""
    echo "📋 Tabelas criadas:"
    if [ -z "$DB_PASS" ]; then
        mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -D "$DB_NAME" -e "SHOW TABLES;" | sed '1d'
    else
        mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASS" -D "$DB_NAME" -e "SHOW TABLES;" | sed '1d'
    fi
    
    # Criar arquivo .env
    echo ""
    echo "🔧 Criando arquivo de configuração..."
    
    ENV_FILE="../.env"
    
    # Gerar chaves secretas seguras
    SESSION_SECRET=$(openssl rand -base64 32)
    JWT_SECRET=$(openssl rand -base64 32)
    
    # Definir usuário e senha para o .env
    if [ "$CREATE_APP_USER" = true ]; then
        FINAL_DB_USER="$APP_USER"
        FINAL_DB_PASS="$APP_PASS"
    else
        FINAL_DB_USER="$DB_USER"
        FINAL_DB_PASS="$DB_PASS"
    fi
    
    # Criar arquivo .env
    cat > "$ENV_FILE" << EOF
# ============================================
# CONFIGURAÇÕES DO BANCO DE DADOS
# ============================================
DB_HOST=$DB_HOST
DB_PORT=$DB_PORT
DB_NAME=$DB_NAME
DB_USER=$FINAL_DB_USER
DB_PASSWORD=$FINAL_DB_PASS
DB_POOL_MIN=2
DB_POOL_MAX=10
DB_CONNECTION_LIMIT=100
DB_QUEUE_LIMIT=0

# ============================================
# CONFIGURAÇÕES DO SERVIDOR
# ============================================
PORT=3000
NODE_ENV=production
HOST=0.0.0.0
SESSION_SECRET=$SESSION_SECRET
JWT_SECRET=$JWT_SECRET
CLIENT_URL=http://localhost:3000
API_URL=http://localhost:3000/api
TRUST_PROXY=1

# ============================================
# CONFIGURAÇÕES DE SEGURANÇA
# ============================================
BCRYPT_ROUNDS=10
JWT_EXPIRES_IN=7d
RATE_LIMIT_WINDOW=15
RATE_LIMIT_MAX=100
CORS_ORIGIN=http://localhost:3000

# ============================================
# CONFIGURAÇÕES DO YOUTUBE
# ============================================
YOUTUBE_API_KEY=SUA_CHAVE_API_AQUI
YOUTUBE_REQUEST_TIMEOUT=30000
YOUTUBE_MAX_RETRIES=3

# ============================================
# CONFIGURAÇÕES DE PROCESSAMENTO
# ============================================
FFMPEG_PATH=/usr/bin/ffmpeg
FFPROBE_PATH=/usr/bin/ffprobe
MAX_CONCURRENT_PROCESSES=3
MAX_VIDEO_DURATION=7200
MAX_FILE_SIZE=104857600
TEMP_DIR=./uploads/temp
UPLOAD_DIR=./uploads
KEEP_VIDEO_DAYS=7
DELETE_TEMP_FILES_AFTER=24

# ============================================
# CONFIGURAÇÕES DE ARMAZENAMENTO
# ============================================
ALLOWED_AUDIO_FORMATS=mp3,wav,flac,ogg,m4a
DEFAULT_AUDIO_QUALITY=128
ENABLE_AUDIO_SEPARATION=true
MAX_SEPARATION_TRACKS=10

# ============================================
# CONFIGURAÇÕES DE EMAIL (OPCIONAL)
# ============================================
# SMTP_HOST=smtp.gmail.com
# SMTP_PORT=587
# SMTP_SECURE=false
# SMTP_USER=seu-email@gmail.com
# SMTP_PASS=sua-senha-app
# EMAIL_FROM=noreply@youraudioextractor.com

# ============================================
# CONFIGURAÇÕES DO GOOGLE OAUTH (OPCIONAL)
# ============================================
# GOOGLE_CLIENT_ID=seu-client-id
# GOOGLE_CLIENT_SECRET=seu-client-secret
# GOOGLE_CALLBACK_URL=http://localhost:3000/api/auth/google/callback

# ============================================
# CONFIGURAÇÕES DE LIMITES
# ============================================
DAILY_LIMIT_FREE=5
DAILY_LIMIT_PREMIUM=50
MAX_DURATION_FREE=1800
MAX_DURATION_PREMIUM=7200

# ============================================
# CONFIGURAÇÕES DE LOG
# ============================================
LOG_LEVEL=info
LOG_FILE=./logs/app.log
LOG_MAX_SIZE=10485760
LOG_MAX_FILES=10

# ============================================
# CONFIGURAÇÕES DE CACHE
# ============================================
CACHE_TTL=3600
ENABLE_CACHE=true
REDIS_HOST=localhost
REDIS_PORT=6379
EOF
    
    log "✅ Arquivo .env criado em: $ENV_FILE"
    
    # Criar arquivo de exemplo
    ENV_EXAMPLE_FILE="../.env.example"
    if [ ! -f "$ENV_EXAMPLE_FILE" ]; then
        cat > "$ENV_EXAMPLE_FILE" << EOF
# Copie este arquivo para .env e ajuste as configurações
DB_HOST=localhost
DB_PORT=3306
DB_NAME=youtube_audio_extractor
DB_USER=usuario_aqui
DB_PASSWORD=senha_aqui

PORT=3000
NODE_ENV=development
SESSION_SECRET=altere_esta_chave_secreta
JWT_SECRET=altere_esta_chave_jwt

YOUTUBE_API_KEY=sua_chave_api_youtube
EOF
        log "✅ Arquivo .env.example criado"
    fi
    
    # Criar diretórios necessários
    echo ""
    echo "📁 Criando diretórios..."
    mkdir -p ../uploads/{audio,video,temp}
    mkdir -p ../logs
    chmod -R 755 ../uploads
    
    # Informações finais
    echo ""
    echo -e "${GREEN}=================================================${NC}"
    echo -e "${BLUE}✅ INSTALAÇÃO DO BANCO CONCLUÍDA!${NC}"
    echo -e "${GREEN}=================================================${NC}"
    echo ""
    echo "📋 RESUMO DA CONFIGURAÇÃO:"
    echo "   Banco de dados: $DB_NAME"
    echo "   Host: $DB_HOST:$DB_PORT"
    
    if [ "$CREATE_APP_USER" = true ]; then
        echo "   Usuário da aplicação: $APP_USER"
    else
        echo "   Usuário: $DB_USER"
    fi
    
    echo "   Arquivo .env: $ENV_FILE"
    echo ""
    echo "⚠️  PRÓXIMOS PASSOS:"
    echo "   1. Edite o arquivo .env com suas configurações reais"
    echo "   2. Configure uma chave da API do YouTube"
    echo "   3. Instale as dependências: npm install"
    echo "   4. Inicie o servidor: npm start"
    echo ""
    echo "🔑 Dica: Para segurança, altere as chaves SESSION_SECRET e JWT_SECRET"
    
else
    error "❌ Erro ao criar banco de dados."
    exit 1
fi
