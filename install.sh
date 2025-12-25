#!/bin/bash
# Arquivo: install.sh
# YouTube Audio Extractor Pro - Instalador Automático VPS

set -e

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }

# Banner
echo -e "${BLUE}"
cat << "EOF"
╔══════════════════════════════════════════════════════════════╗
║      🎵 YOUTUBE AUDIO EXTRACTOR PRO - INSTALADOR VPS        ║
║              Node.js + MariaDB + Ubuntu 22.04               ║
╚══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Verificar root
if [[ $EUID -ne 0 ]]; then
    error "Execute como root: sudo bash $0"
fi

# Variáveis configuráveis
SITE_DIR="/var/www/youtube-extractor-pro"
REPO_URL="https://github.com/seu-usuario/youtube-extractor-pro/archive/refs/heads/main.zip"
ZIP_FILE="/tmp/youtube-extractor-pro.zip"

# 1. Atualizar sistema
log "Atualizando sistema..."
apt update && apt upgrade -y

# 2. Criar diretório do site
log "Criando diretório do site em $SITE_DIR..."
mkdir -p $SITE_DIR
chown -R $SUDO_USER:$SUDO_USER $SITE_DIR
chmod 755 $SITE_DIR

# 3. Instalar Node.js
log "Instalando Node.js 18.x..."
curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt install -y nodejs npm
npm install -g pm2

# 4. Instalar MariaDB
log "Instalando MariaDB..."
apt install -y mariadb-server mariadb-client
systemctl start mariadb
systemctl enable mariadb

# 5. Instalar dependências do sistema
log "Instalando dependências do sistema..."
apt install -y nginx ffmpeg git curl wget unzip build-essential

# 6. Configurar banco de dados
log "Configurando banco de dados..."
mysql -e "CREATE DATABASE IF NOT EXISTS youtube_extractor;" 2>/dev/null || warn "Erro ao criar BD (pode já existir)"
mysql -e "CREATE USER IF NOT EXISTS 'youtube_user'@'localhost' IDENTIFIED BY 'YoutubePass123!';" 2>/dev/null || warn "Erro ao criar usuário"
mysql -e "GRANT ALL PRIVILEGES ON youtube_extractor.* TO 'youtube_user'@'localhost';" 2>/dev/null || warn "Erro ao conceder privilégios"
mysql -e "FLUSH PRIVILEGES;" 2>/dev/null || warn "Erro ao atualizar privilégios"

# 7. Baixar e extrair o site do GitHub
log "Baixando site do GitHub..."
cd /tmp
if command -v wget &> /dev/null; then
    wget -O $ZIP_FILE $REPO_URL
elif command -v curl &> /dev/null; then
    curl -L -o $ZIP_FILE $REPO_URL
else
    error "Necessário wget ou curl para baixar o site"
fi

log "Extraindo arquivos para $SITE_DIR..."
unzip -q -o $ZIP_FILE -d /tmp/

# Encontrar e copiar arquivos extraídos
if [ -d "/tmp/youtube-extractor-pro-main" ]; then
    cp -r /tmp/youtube-extractor-pro-main/* $SITE_DIR/
    cp -r /tmp/youtube-extractor-pro-main/. $SITE_DIR/ 2>/dev/null || true
elif [ -d "/tmp/main" ]; then
    cp -r /tmp/main/* $SITE_DIR/
    cp -r /tmp/main/. $SITE_DIR/ 2>/dev/null || true
else
    # Tentar encontrar qualquer diretório extraído
    EXTRACTED_DIR=$(find /tmp -type d -name "*youtube*extractor*" -o -name "*youtube*" | head -1)
    if [ -n "$EXTRACTED_DIR" ] && [ -d "$EXTRACTED_DIR" ]; then
        cp -r "$EXTRACTED_DIR"/* $SITE_DIR/
        cp -r "$EXTRACTED_DIR"/. $SITE_DIR/ 2>/dev/null || true
    else
        warn "Não foi possível encontrar arquivos extraídos. Extraindo diretamente..."
        unzip -q -o $ZIP_FILE -d $SITE_DIR
    fi
fi

# Limpar arquivos temporários
rm -f $ZIP_FILE
rm -rf /tmp/youtube-extractor-pro-main /tmp/main

# 8. Verificar estrutura do projeto
log "Verificando estrutura do projeto..."
cd $SITE_DIR

# Criar estrutura de diretórios se não existir
mkdir -p backend frontend uploads

# 9. Instalar dependências do Node.js
log "Instalando dependências do Node.js..."

# Procurar package.json em diferentes locais
if [ -f "$SITE_DIR/backend/package.json" ]; then
    log "Instalando dependências do backend..."
    cd $SITE_DIR/backend
    npm install --production --no-audit
elif [ -f "$SITE_DIR/package.json" ]; then
    log "Instalando dependências do projeto..."
    cd $SITE_DIR
    npm install --production --no-audit
else
    warn "Nenhum package.json encontrado. Criando estrutura básica..."
    
    # Criar package.json básico para Node.js
    cat > $SITE_DIR/package.json << 'EOF'
{
  "name": "youtube-extractor-pro",
  "version": "1.0.0",
  "description": "YouTube Audio Extractor Pro",
  "main": "server.js",
  "scripts": {
    "start": "node server.js",
    "dev": "nodemon server.js",
    "test": "echo \"Error: no test specified\" && exit 1"
  },
  "dependencies": {
    "express": "^4.18.2",
    "cors": "^2.8.5",
    "mysql2": "^3.6.0",
    "ytdl-core": "^4.11.5",
    "fluent-ffmpeg": "^2.1.2",
    "dotenv": "^16.3.1",
    "socket.io": "^4.7.2"
  },
  "engines": {
    "node": ">=18.0.0"
  }
}
EOF
    
    # Criar server.js básico
    cat > $SITE_DIR/server.js << 'EOF'
const express = require('express');
const cors = require('cors');
const path = require('path');
const app = express();
const port = process.env.PORT || 3000;

// Middleware
app.use(cors());
app.use(express.json());
app.use(express.static(path.join(__dirname, 'frontend')));

// Rotas
app.get('/api/health', (req, res) => {
    res.json({ 
        status: 'ok', 
        message: 'YouTube Audio Extractor Pro está funcionando!',
        version: '1.0.0'
    });
});

app.get('/api/config', (req, res) => {
    res.json({
        nodeVersion: process.version,
        platform: process.platform,
        uptime: process.uptime()
    });
});

// Rota para frontend
app.get('*', (req, res) => {
    res.sendFile(path.join(__dirname, 'frontend', 'index.html'));
});

app.listen(port, () => {
    console.log(`✅ Servidor rodando na porta ${port}`);
    console.log(`📁 Diretório: ${__dirname}`);
    console.log(`🌐 Acesse: http://localhost:${port}`);
});
EOF
    
    # Criar frontend básico se não existir
    mkdir -p $SITE_DIR/frontend
    cat > $SITE_DIR/frontend/index.html << 'EOF'
<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>YouTube Audio Extractor Pro</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { 
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            color: white;
        }
        .container {
            text-align: center;
            max-width: 800px;
            padding: 2rem;
            background: rgba(255, 255, 255, 0.1);
            backdrop-filter: blur(10px);
            border-radius: 20px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
        }
        h1 { 
            font-size: 3rem; 
            margin-bottom: 1rem;
            background: linear-gradient(45deg, #ff6b6b, #feca57);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
        }
        .status { 
            background: rgba(0, 0, 0, 0.2); 
            padding: 1rem; 
            border-radius: 10px;
            margin: 2rem 0;
        }
        .features {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 1rem;
            margin: 2rem 0;
        }
        .feature {
            background: rgba(255, 255, 255, 0.1);
            padding: 1.5rem;
            border-radius: 10px;
            transition: transform 0.3s;
        }
        .feature:hover {
            transform: translateY(-5px);
        }
        .icon { font-size: 2rem; margin-bottom: 1rem; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🎵 YouTube Audio Extractor Pro</h1>
        <p style="font-size: 1.2rem; opacity: 0.9;">Sistema instalado com sucesso!</p>
        
        <div class="status">
            <p id="status">Verificando status do sistema...</p>
        </div>
        
        <div class="features">
            <div class="feature">
                <div class="icon">⚡</div>
                <h3>Rápido</h3>
                <p>Extraia áudio do YouTube em segundos</p>
            </div>
            <div class="feature">
                <div class="icon">🎧</div>
                <h3>Qualidade</h3>
                <p>Suporte a múltiplos formatos de áudio</p>
            </div>
            <div class="feature">
                <div class="icon">📁</div>
                <h3>Organizado</h3>
                <p>Gerenciamento de downloads fácil</p>
            </div>
        </div>
        
        <div style="margin-top: 2rem;">
            <p>Configure o sistema editando o arquivo <code>.env</code></p>
            <p style="font-size: 0.9rem; opacity: 0.7; margin-top: 1rem;">
                Instalado em: <code>/var/www/youtube-extractor-pro</code>
            </p>
        </div>
    </div>
    
    <script>
        // Verificar status da API
        fetch('/api/health')
            .then(response => response.json())
            .then(data => {
                document.getElementById('status').innerHTML = 
                    `✅ ${data.message}<br><small>Sistema operacional normalmente</small>`;
            })
            .catch(error => {
                document.getElementById('status').innerHTML = 
                    `⚠️ API não respondendo. Verifique o servidor Node.js.<br>
                     <small>Erro: ${error.message}</small>`;
            });
        
        // Obter informações do sistema
        fetch('/api/config')
            .then(response => response.json())
            .then(data => {
                console.log('Configuração do sistema:', data);
            });
    </script>
</body>
</html>
EOF
    
    cd $SITE_DIR
    npm install --production --no-audit
    log "Estrutura básica criada e dependências instaladas."
fi

# 10. Configurar Nginx
log "Configurando Nginx..."
cat > /etc/nginx/sites-available/youtube-extractor << NGINX
server {
    listen 80;
    listen [::]:80;
    server_name _;
    
    # Diretório raiz do site
    root $SITE_DIR/frontend;
    index index.html index.htm;
    
    # Configuração do frontend - Single Page Application
    location / {
        try_files \$uri \$uri/ /index.html;
    }
    
    # API Proxy - Node.js backend
    location /api/ {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
    }
    
    # WebSocket support
    location /socket.io/ {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
    
    # Uploads directory
    location /uploads/ {
        alias $SITE_DIR/uploads/;
        expires 30d;
        add_header Cache-Control "public, immutable";
        autoindex off;
    }
    
    # Static files cache
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot|mp3|mp4|webm)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        try_files \$uri =404;
    }
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    
    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css text/xml text/javascript application/javascript application/xml+rss application/json;
}
NGINX

# Habilitar site
ln -sf /etc/nginx/sites-available/youtube-extractor /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Testar e reiniciar Nginx
nginx -t && systemctl restart nginx
log "Nginx configurado e reiniciado."

# 11. Configurar firewall (opcional)
if command -v ufw &> /dev/null; then
    log "Configurando firewall..."
    ufw --force enable 2>/dev/null || true
    ufw allow OpenSSH 2>/dev/null || warn "Erro ao configurar firewall OpenSSH"
    ufw allow 'Nginx Full' 2>/dev/null || warn "Erro ao configurar firewall Nginx"
    ufw --force reload 2>/dev/null || true
else
    warn "UFW não encontrado. Configure o firewall manualmente se necessário."
fi

# 12. Iniciar aplicação com PM2
log "Iniciando aplicação com PM2..."

# Determinar o arquivo principal
if [ -f "$SITE_DIR/backend/server.js" ]; then
    MAIN_FILE="$SITE_DIR/backend/server.js"
    START_DIR="$SITE_DIR/backend"
elif [ -f "$SITE_DIR/server.js" ]; then
    MAIN_FILE="$SITE_DIR/server.js"
    START_DIR="$SITE_DIR"
elif [ -f "$SITE_DIR/app.js" ]; then
    MAIN_FILE="$SITE_DIR/app.js"
    START_DIR="$SITE_DIR"
else
    MAIN_FILE="$SITE_DIR/server.js"
    START_DIR="$SITE_DIR"
fi

cd $START_DIR

# Parar instância existente se houver
pm2 delete youtube-extractor 2>/dev/null || true

# Iniciar aplicação
pm2 start $MAIN_FILE --name "youtube-extractor" --time
pm2 save

# Configurar startup do PM2
if [ -f "/etc/systemd/system/pm2-root.service" ]; then
    systemctl daemon-reload
    systemctl enable pm2-root
else
    pm2 startup 2>/dev/null | tail -1 | bash 2>/dev/null || warn "Configure o PM2 startup manualmente: pm2 startup"
fi

pm2 list

# 13. Criar diretórios necessários
log "Criando diretórios necessários..."
mkdir -p $SITE_DIR/uploads/{videos,audio,temp,converted}
chown -R www-data:www-data $SITE_DIR/uploads
chmod -R 755 $SITE_DIR/uploads

# Configurar permissões do diretório principal
chown -R $SUDO_USER:www-data $SITE_DIR
chmod -R 755 $SITE_DIR
find $SITE_DIR -type f -exec chmod 644 {} \;
find $SITE_DIR -type d -exec chmod 755 {} \;

# 14. Criar arquivo .env se necessário
if [ ! -f "$SITE_DIR/.env" ] && [ ! -f "$SITE_DIR/backend/.env" ]; then
    ENV_FILE="$SITE_DIR/.env"
    cat > $ENV_FILE << 'EOF'
# Configurações do Banco de Dados
DB_HOST=localhost
DB_PORT=3306
DB_NAME=youtube_extractor
DB_USER=youtube_user
DB_PASSWORD=YoutubePass123!

# Configurações do Servidor
PORT=3000
NODE_ENV=production
HOST=0.0.0.0
SESSION_SECRET=$(openssl rand -hex 32)

# Configurações do YouTube
YOUTUBE_API_KEY=your_api_key_here

# Configurações de FFmpeg
FFMPEG_PATH=/usr/bin/ffmpeg
FFPROBE_PATH=/usr/bin/ffprobe

# Configurações de Upload
MAX_FILE_SIZE=104857600 # 100MB
UPLOAD_PATH=./uploads
ALLOWED_FORMATS=mp3,mp4,wav,aac,flac

# Configurações do Redis (opcional)
REDIS_HOST=localhost
REDIS_PORT=6379

# Configurações de Log
LOG_LEVEL=info
LOG_FILE=./logs/app.log

# Configurações de Rate Limiting
RATE_LIMIT_WINDOW=15
RATE_LIMIT_MAX=100
EOF
    chmod 600 $ENV_FILE
    log "Arquivo .env criado com configurações padrão"
fi

# 15. Criar script de manutenção
cat > /usr/local/bin/youtube-extractor-manage << 'EOF'
#!/bin/bash
case "$1" in
    start)
        cd /var/www/youtube-extractor-pro
        pm2 start youtube-extractor
        ;;
    stop)
        pm2 stop youtube-extractor
        ;;
    restart)
        pm2 restart youtube-extractor
        ;;
    status)
        pm2 status youtube-extractor
        ;;
    logs)
        pm2 logs youtube-extractor
        ;;
    update)
        cd /var/www/youtube-extractor-pro
        git pull origin main
        npm install --production
        pm2 restart youtube-extractor
        ;;
    *)
        echo "Uso: $0 {start|stop|restart|status|logs|update}"
        exit 1
        ;;
esac
EOF

chmod +x /usr/local/bin/youtube-extractor-manage

# 16. Finalização
log "Instalação concluída com sucesso!"
echo ""
echo -e "${GREEN}=================================================${NC}"
echo -e "${BLUE}🎵 YouTube Audio Extractor Pro Instalado!${NC}"
echo -e "${GREEN}=================================================${NC}"
echo ""
echo "📁 Diretório do site: $SITE_DIR"
echo "🌐 URL de acesso: http://$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}' || echo 'seu-ip')"
echo "🚀 Servidor Node.js: porta 3000 (proxy via Nginx)"
echo "💾 Banco de dados: MariaDB (youtube_extractor)"
echo ""
echo "🛠️  Comandos de gerenciamento:"
echo "   • youtube-extractor-manage start    # Iniciar"
echo "   • youtube-extractor-manage stop     # Parar"
echo "   • youtube-extractor-manage restart  # Reiniciar"
echo "   • youtube-extractor-manage status   # Status"
echo "   • youtube-extractor-manage logs     # Ver logs"
echo "   • youtube-extractor-manage update   # Atualizar"
echo ""
echo "📋 Próximos passos IMPORTANTES:"
echo "   1. Edite $SITE_DIR/.env com suas configurações reais"
echo "   2. Configure uma chave de API do YouTube válida"
echo "   3. Para SSL/TLS (HTTPS): certbot --nginx"
echo "   4. Configure backups periódicos do banco de dados"
echo ""
echo -e "${GREEN}✅ Site está online e pronto para navegação!${NC}"
echo ""
