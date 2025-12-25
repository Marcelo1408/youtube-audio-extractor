#!/bin/bash
# install-sql.sh - Script de instalação do banco de dados (VERSÃO CORRIGIDA)
# Baixa schema.sql automaticamente do GitHub

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

# URL do schema.sql no GitHub
SCHEMA_GITHUB_URL="https://raw.githubusercontent.com/Marcelo1408/youtube-audio-extractor/main/schema.sql"
LOCAL_SCHEMA_FILE="/tmp/schema_$(date +%s).sql"

echo "📥 Baixando schema.sql do GitHub..."
if command -v curl &> /dev/null; then
    if curl -sSL "$SCHEMA_GITHUB_URL" -o "$LOCAL_SCHEMA_FILE"; then
        if [ -s "$LOCAL_SCHEMA_FILE" ]; then
            log "Schema baixado com sucesso!"
        else
            error "Arquivo schema.sql vazio ou inválido!"
            exit 1
        fi
    else
        error "Falha ao baixar schema.sql do GitHub!"
        exit 1
    fi
elif command -v wget &> /dev/null; then
    if wget -q "$SCHEMA_GITHUB_URL" -O "$LOCAL_SCHEMA_FILE"; then
        if [ -s "$LOCAL_SCHEMA_FILE" ]; then
            log "Schema baixado com sucesso!"
        else
            error "Arquivo schema.sql vazio ou inválido!"
            exit 1
        fi
    else
        error "Falha ao baixar schema.sql do GitHub!"
        exit 1
    fi
else
    error "Necessário curl ou wget para baixar o schema!"
    echo "Instale: sudo apt install curl"
    exit 1
fi

# Verificar se MariaDB/MySQL está instalado
if ! command -v mysql &> /dev/null; then
    error "MariaDB/MySQL não está instalado."
    echo "Para instalar:"
    echo "  sudo apt update && sudo apt install -y mariadb-server"
    echo "  sudo systemctl start mariadb && sudo systemctl enable mariadb"
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

# Criar banco de dados
echo ""
echo "📊 Criando banco de dados..."
echo "---------------------------------"

# Preparar comandos SQL
SQL_COMMANDS="
-- Criar banco de dados
CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

USE \`$DB_NAME\`;
"

# Adicionar conteúdo do schema.sql
SQL_COMMANDS+=$(cat "$LOCAL_SCHEMA_FILE")

# Adicionar usuário da aplicação se solicitado
if [ "$CREATE_APP_USER" = true ]; then
    SQL_COMMANDS+="
-- Criar usuário para a aplicação
CREATE USER IF NOT EXISTS '$APP_USER'@'$DB_HOST' IDENTIFIED BY '$APP_PASS';

-- Conceder permissões
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$APP_USER'@'$DB_HOST';

-- Conceder permissão para criar eventos
GRANT EVENT ON \`$DB_NAME\`.* TO '$APP_USER'@'$DB_HOST';

-- Atualizar privilégios
FLUSH PRIVILEGES;
"
fi

# Executar SQL
echo "Executando comandos SQL..."
if [ -z "$DB_PASS" ]; then
    mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -e "$SQL_COMMANDS"
    EXIT_CODE=$?
else
    mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASS" -e "$SQL_COMMANDS"
    EXIT_CODE=$?
fi

if [ $EXIT_CODE -eq 0 ]; then
    log "✅ Banco de dados criado com sucesso!"
    
    # Verificar tabelas criadas
    echo ""
    echo "📋 Tabelas criadas:"
    if [ -z "$DB_PASS" ]; then
        mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -D "$DB_NAME" -e "SHOW TABLES;" | sed '1d'
    else
        mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASS" -D "$DB_NAME" -e "SHOW TABLES;" | sed '1d'
    fi
    
    # Criar diretório atual para .env
    CURRENT_DIR="$(pwd)"
    ENV_FILE="$CURRENT_DIR/.env"
    
    # Verificar se estamos em algum subdiretório
    if [[ "$CURRENT_DIR" == *"backend"* ]] || [[ "$CURRENT_DIR" == *"database"* ]]; then
        ENV_FILE="$(dirname "$CURRENT_DIR")/.env"
    fi
    
    # Criar arquivo .env
    echo ""
    echo "🔧 Criando arquivo de configuração em: $ENV_FILE"
    
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

# ============================================
# CONFIGURAÇÕES DO SERVIDOR
# ============================================
PORT=3000
NODE_ENV=production
SESSION_SECRET=$SESSION_SECRET
JWT_SECRET=$JWT_SECRET
CLIENT_URL=http://localhost:3000

# ============================================
# CONFIGURAÇÕES DO YOUTUBE
# ============================================
YOUTUBE_API_KEY=SUA_CHAVE_API_AQUI

# ============================================
# CONFIGURAÇÕES DE PROCESSAMENTO
# ============================================
FFMPEG_PATH=/usr/bin/ffmpeg
MAX_FILE_SIZE=104857600
UPLOAD_DIR=./uploads
TEMP_DIR=./uploads/temp

# ============================================
# CONFIGURAÇÕES DE LIMITES
# ============================================
DAILY_LIMIT_FREE=5
DAILY_LIMIT_PREMIUM=50
MAX_DURATION_FREE=1800
MAX_DURATION_PREMIUM=7200
EOF
    
    log "✅ Arquivo .env criado!"
    
    # Criar arquivo .env.example se não existir
    ENV_EXAMPLE_FILE="$(dirname "$ENV_FILE")/.env.example"
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
    
    # Informações finais
    echo ""
    echo -e "${GREEN}=================================================${NC}"
    echo -e "${BLUE}✅ INSTALAÇÃO DO BANCO CONCLUÍDA!${NC}"
    echo -e "${GREEN}=================================================${NC}"
    echo ""
    echo "📋 RESUMO:"
    echo "   Banco: $DB_NAME"
    echo "   Host: $DB_HOST:$DB_PORT"
    echo "   Usuário: $FINAL_DB_USER"
    echo "   Arquivo .env: $ENV_FILE"
    echo ""
    echo "⚠️  PRÓXIMOS PASSOS:"
    echo "   1. Configure YOUTUBE_API_KEY no arquivo .env"
    echo "   2. Execute: npm install"
    echo "   3. Execute: npm start"
    echo ""
    echo "🔧 Para testar a conexão:"
    echo "   mysql -h $DB_HOST -P $DB_PORT -u $FINAL_DB_USER -p'SUA_SENHA' -D $DB_NAME"
    
else
    error "❌ Erro ao criar banco de dados."
    
    # Tentar diagnóstico
    echo ""
    echo "🔍 Tentando diagnóstico..."
    
    # Verificar se o banco foi criado
    if [ -z "$DB_PASS" ]; then
        mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -e "SHOW DATABASES LIKE '$DB_NAME';" | grep -q "$DB_NAME"
    else
        mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASS" -e "SHOW DATABASES LIKE '$DB_NAME';" | grep -q "$DB_NAME"
    fi
    
    if [ $? -eq 0 ]; then
        warn "Banco de dados foi criado, mas houve erro nas tabelas."
        echo "Tente executar o schema.sql manualmente:"
        echo "mysql -u $FINAL_DB_USER -p $DB_NAME < schema.sql"
    fi
    
    exit 1
fi

# Limpar arquivo temporário
rm -f "$LOCAL_SCHEMA_FILE"

# Verificar se o usuário quer criar diretórios
read -p "📁 Criar diretórios de uploads? (s/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Ss]$ ]]; then
    BASE_DIR="$(dirname "$ENV_FILE")"
    mkdir -p "$BASE_DIR/uploads"{/audio,/video,/temp}
    mkdir -p "$BASE_DIR/logs"
    chmod -R 755 "$BASE_DIR/uploads"
    log "Diretórios criados em: $BASE_DIR"
fi
