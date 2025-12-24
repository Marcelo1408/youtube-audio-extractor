#!/bin/bash

# YouTube Audio Extractor - Instalador Simplificado
# Versão: 3.0.0
# Autor: Sistema YouTube Audio Extractor

set -e

# ============================================================================
# CONFIGURAÇÕES FIXAS (USE SUAS CREDENCIAIS)
# ============================================================================

# Credenciais DO SEU SISTEMA (do seu .env/config.php)
DB_DATABASE="audioextractor"
DB_USERNAME="audioextrac_usr"
DB_PASSWORD="3GqG!%Yg7i;YsI4Y"

# Configurações do sistema
DOMAIN_NAME="audioextractor.giize.com"
EMAIL_ADMIN="mpnascimento031@gmail.com"
INSTALL_DIR="/var/www/youtube-audio-extractor"

# Senhas geradas
ADMIN_PASSWORD=$(openssl rand -base64 12)
SECRET_KEY=$(openssl rand -base64 48)

# ============================================================================
# FUNÇÕES BÁSICAS
# ============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[AVISO]${NC} $1"; }
error() { echo -e "${RED}[ERRO]${NC} $1"; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "Execute como root: sudo ./install.sh"
        exit 1
    fi
}

# ============================================================================
# INSTALAÇÃO DIRETA
# ============================================================================

install_dependencies() {
    log "Atualizando sistema..."
    apt update && apt upgrade -y
    
    log "Instalando dependências..."
    apt install -y \
        apache2 \
        mariadb-server \
        mariadb-client \
        software-properties-common \
        curl \
        wget \
        git \
        unzip \
        python3 \
        python3-pip \
        python3-venv \
        ffmpeg \
        redis-server \
        supervisor \
        certbot \
        python3-certbot-apache
    
    log "Instalando PHP 8.2..."
    add-apt-repository -y ppa:ondrej/php
    apt update
    apt install -y \
        php8.2 php8.2-cli php8.2-mysql php8.2-curl php8.2-gd \
        php8.2-mbstring php8.2-xml php8.2-zip php8.2-bcmath \
        libapache2-mod-php8.2
}

setup_mysql() {
    log "Configurando MySQL..."
    
    # Iniciar MySQL se não estiver rodando
    systemctl start mariadb 2>/dev/null || systemctl start mysql 2>/dev/null
    
    echo ""
    echo "================================================================================"
    echo "CONFIGURAÇÃO DO MYSQL"
    echo "================================================================================"
    echo ""
    echo "O MySQL/MariaDB precisa ser configurado."
    echo ""
    echo "1. Para Ubuntu/Debian, geralmente você pode acessar com: sudo mysql"
    echo "2. Se já configurou senha, use: mysql -u root -p"
    echo "3. Se não sabe, execute primeiro: sudo mysql_secure_installation"
    echo ""
    echo "Vou te ajudar a configurar. Escolha uma opção:"
    echo ""
    echo "a) Já tenho acesso ao MySQL (pressione Enter para pular)"
    echo "b) Quero configurar agora com mysql_secure_installation"
    echo "c) Quero acessar manualmente e depois continuar"
    echo ""
    
    read -p "Sua escolha (a/b/c): " mysql_choice
    
    case $mysql_choice in
        b)
            echo "Executando mysql_secure_installation..."
            mysql_secure_installation
            ;;
        c)
            echo "Acesse o MySQL manualmente. Depois volte e pressione Enter."
            echo "Comandos úteis:"
            echo "  sudo mysql"
            echo "  ou"
            echo "  mysql -u root -p"
            read -p "Pressione Enter após configurar o MySQL..."
            ;;
        *)
            echo "Pulando configuração do MySQL..."
            ;;
    esac
    
    echo ""
    echo "Agora preciso criar o banco de dados do sistema."
    echo "Vou usar estas credenciais DO SEU SISTEMA:"
    echo "  Banco: $DB_DATABASE"
    echo "  Usuário: $DB_USERNAME"
    echo ""
    echo "Preciso acessar o MySQL como root para criar o banco."
    echo ""
    
    # Tentar diferentes formas de acesso
    if mysql -u root -e "SELECT 1;" 2>/dev/null; then
        echo "✅ Consegui acessar MySQL sem senha"
        MYSQL_CMD="mysql -u root"
    elif sudo mysql -e "SELECT 1;" 2>/dev/null; then
        echo "✅ Consegui acessar MySQL com sudo"
        MYSQL_CMD="sudo mysql"
    else
        echo "⚠️  Não consegui acessar automaticamente."
        echo "Por favor, digite o comando para acessar o MySQL como root:"
        echo "Exemplos:"
        echo "  mysql -u root"
        echo "  mysql -u root -p"
        echo "  sudo mysql"
        echo ""
        read -p "Comando MySQL: " mysql_cmd
        MYSQL_CMD="$mysql_cmd"
        
        # Testar o comando
        if ! $MYSQL_CMD -e "SELECT 1;" 2>/dev/null; then
            error "Não foi possível acessar com esse comando."
            warn "Vou pular a criação do banco. Você pode criar manualmente depois."
            return 1
        fi
    fi
    
    # Criar banco de dados
    log "Criando banco de dados..."
    $MYSQL_CMD <<EOF
CREATE DATABASE IF NOT EXISTS \`$DB_DATABASE\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '$DB_USERNAME'@'localhost' IDENTIFIED BY '$DB_PASSWORD';
GRANT ALL PRIVILEGES ON \`$DB_DATABASE\`.* TO '$DB_USERNAME'@'localhost';
FLUSH PRIVILEGES;
EOF
    
    if [ $? -eq 0 ]; then
        log "Banco de dados criado com sucesso!"
        echo "  Banco: $DB_DATABASE"
        echo "  Usuário: $DB_USERNAME"
        echo "  Senha: [sua senha configurada]"
    else
        warn "Não foi possível criar o banco automaticamente."
        warn "Crie manualmente depois com:"
        warn "  CREATE DATABASE $DB_DATABASE;"
        warn "  CREATE USER '$DB_USERNAME'@'localhost' IDENTIFIED BY 'SUA_SENHA';"
        warn "  GRANT ALL ON $DB_DATABASE.* TO '$DB_USERNAME'@'localhost';"
    fi
}

setup_website() {
    log "Configurando site..."
    
    # Clonar ou usar diretório existente
    if [ -d "$INSTALL_DIR" ]; then
        warn "Diretório $INSTALL_DIR já existe. Usando existente."
    else
        mkdir -p "$INSTALL_DIR"
        
        # Criar index.php básico
        cat > "$INSTALL_DIR/index.php" <<EOF
<!DOCTYPE html>
<html>
<head>
    <title>YouTube Audio Extractor</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        .container { max-width: 800px; margin: 0 auto; }
        .header { background: #4CAF50; color: white; padding: 20px; border-radius: 5px; }
        .content { padding: 20px; border: 1px solid #ddd; margin-top: 20px; border-radius: 5px; }
        .success { color: green; }
        .error { color: red; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🎵 YouTube Audio Extractor</h1>
            <p>Sistema instalado com sucesso!</p>
        </div>
        <div class="content">
            <h2>✅ Sistema Pronto</h2>
            
            <?php
            // Testar MySQL
            \$mysqli = new mysqli('localhost', '$DB_USERNAME', '$DB_PASSWORD', '$DB_DATABASE');
            if (\$mysqli->connect_error) {
                echo '<p class="error">❌ Erro MySQL: ' . \$mysqli->connect_error . '</p>';
            } else {
                echo '<p class="success">✅ Conexão MySQL OK</p>';
                \$mysqli->close();
            }
            
            // Testar PHP
            echo '<p class="success">✅ PHP ' . phpversion() . ' funcionando</p>';
            ?>
            
            <h3>📊 Informações</h3>
            <p><strong>Domínio:</strong> <?php echo \$_SERVER['HTTP_HOST'] ?? '$DOMAIN_NAME'; ?></p>
            <p><strong>Data:</strong> <?php echo date('d/m/Y H:i:s'); ?></p>
            
            <h3>🔧 Próximos Passos</h3>
            <ol>
                <li>Configure os arquivos do sistema em $INSTALL_DIR</li>
                <li>Configure o .env com suas credenciais</li>
                <li>Acesse o painel admin em /admin</li>
            </ol>
        </div>
    </div>
</body>
</html>
EOF
    fi
    
    # Criar .env básico
    cat > "$INSTALL_DIR/.env" <<EOF
APP_NAME=YouTube Audio Extractor
APP_ENV=production
APP_DEBUG=false
APP_URL=https://$DOMAIN_NAME
APP_KEY=$SECRET_KEY

# SEU BANCO DE DADOS
DB_CONNECTION=mysql
DB_HOST=localhost
DB_PORT=3306
DB_DATABASE=$DB_DATABASE
DB_USERNAME=$DB_USERNAME
DB_PASSWORD=$DB_PASSWORD

CACHE_DRIVER=file
SESSION_DRIVER=file
QUEUE_DRIVER=sync

MAIL_MAILER=smtp
MAIL_HOST=localhost
MAIL_PORT=25
MAIL_USERNAME=
MAIL_PASSWORD=
MAIL_FROM_ADDRESS=$EMAIL_ADMIN
MAIL_FROM_NAME="YouTube Audio Extractor"
EOF
    
    # Configurar Apache
    log "Configurando Apache..."
    cat > /etc/apache2/sites-available/audioextractor.conf <<EOF
<VirtualHost *:80>
    ServerName $DOMAIN_NAME
    ServerAdmin $EMAIL_ADMIN
    DocumentRoot $INSTALL_DIR
    
    ErrorLog \${APACHE_LOG_DIR}/audioextractor-error.log
    CustomLog \${APACHE_LOG_DIR}/audioextractor-access.log combined
    
    <Directory $INSTALL_DIR>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    
    php_value upload_max_filesize 2G
    php_value post_max_size 2G
    php_value max_execution_time 600
    php_value memory_limit 1G
</VirtualHost>
EOF
    
    a2dissite 000-default.conf 2>/dev/null
    a2ensite audioextractor.conf
    systemctl restart apache2
}

setup_ssl() {
    log "Configurando SSL..."
    
    echo ""
    echo "Para configurar SSL, seu domínio precisa apontar para este servidor."
    echo "Domínio: $DOMAIN_NAME"
    echo "IP do servidor: 45.140.193.50"
    echo ""
    echo "Configure o DNS primeiro, depois execute:"
    echo "  sudo certbot --apache -d $DOMAIN_NAME"
    echo ""
    
    read -p "O DNS já está configurado? (s/n): " -n 1 dns_ready
    echo
    
    if [[ $dns_ready =~ ^[Ss]$ ]]; then
        if certbot --apache -d "$DOMAIN_NAME" --non-interactive --agree-tos --email "$EMAIL_ADMIN"; then
            log "SSL configurado com sucesso!"
        else
            warn "Falha ao configurar SSL. Configure manualmente depois."
        fi
    else
        warn "SSL não configurado. Configure depois com:"
        warn "  sudo certbot --apache -d $DOMAIN_NAME"
    fi
}

setup_python_tools() {
    log "Configurando ferramentas Python..."
    
    # Criar ambiente virtual
    python3 -m venv /opt/audioenv
    
    # Instalar yt-dlp
    /opt/audioenv/bin/pip install yt-dlp pydub redis requests
}

setup_firewall() {
    log "Configurando firewall..."
    
    # Instalar UFW se não existir
    if ! command -v ufw &>/dev/null; then
        apt install -y ufw
    fi
    
    ufw allow 22/tcp
    ufw allow 80/tcp
    ufw allow 443/tcp
    echo "y" | ufw enable 2>/dev/null || true
}

show_summary() {
    clear
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║         ✅ INSTALAÇÃO CONCLUÍDA!                             ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    
    echo "📋 RESUMO DA INSTALAÇÃO"
    echo "========================"
    echo ""
    echo "🌐 DOMÍNIO: $DOMAIN_NAME"
    echo "📁 DIRETÓRIO: $INSTALL_DIR"
    echo "📧 EMAIL: $EMAIL_ADMIN"
    echo ""
    
    echo "🗄️  BANCO DE DADOS (SUAS CREDENCIAIS)"
    echo "----------------------------------------"
    echo "Banco: $DB_DATABASE"
    echo "Usuário: $DB_USERNAME"
    echo "Senha: [sua senha configurada]"
    echo ""
    
    echo "🔧 CONFIGURAÇÃO"
    echo "----------------"
    echo "• Apache instalado e configurado"
    echo "• MySQL/MariaDB instalado"
    echo "• PHP 8.2 instalado"
    echo "• yt-dlp e ferramentas Python configuradas"
    echo ""
    
    echo "🚀 PRÓXIMOS PASSOS"
    echo "=================="
    echo ""
    echo "1. CONFIGURE O DNS (IMPORTANTE!)"
    echo "   Domínio: $DOMAIN_NAME"
    echo "   Apontar para: 45.140.193.50"
    echo ""
    echo "2. Após DNS propagar, configure SSL:"
    echo "   sudo certbot --apache -d $DOMAIN_NAME"
    echo ""
    echo "3. Copie seus arquivos do sistema para:"
    echo "   $INSTALL_DIR"
    echo ""
    echo "4. Configure o .env com suas credenciais:"
    echo "   nano $INSTALL_DIR/.env"
    echo ""
    echo "5. Acesse o sistema:"
    echo "   https://$DOMAIN_NAME"
    echo ""
    
    echo "⚙️  COMANDOS ÚTEIS"
    echo "=================="
    echo "• Testar MySQL: mysql -u $DB_USERNAME -p $DB_DATABASE"
    echo "• Reiniciar Apache: sudo systemctl restart apache2"
    echo "• Ver logs: sudo tail -f /var/log/apache2/audioextractor-*.log"
    echo "• Acessar diretório: cd $INSTALL_DIR"
    echo ""
    
    # Salvar credenciais
    cat > /root/install_summary.txt <<EOF
========================================
INSTALAÇÃO YOUTUBE AUDIO EXTRACTOR
========================================
Data: $(date)

SISTEMA
-------
URL: https://$DOMAIN_NAME
Diretório: $INSTALL_DIR
Email: $EMAIL_ADMIN

BANCO DE DADOS
--------------
Host: localhost
Banco: $DB_DATABASE
Usuário: $DB_USERNAME
Senha: [sua senha configurada]

DNS
---
Domínio: $DOMAIN_NAME
IP do servidor: 45.140.193.50

COMANDOS
--------
Configurar SSL: sudo certbot --apache -d $DOMAIN_NAME
Acessar MySQL: mysql -u $DB_USERNAME -p $DB_DATABASE
Reiniciar Apache: sudo systemctl restart apache2
========================================
EOF
    
    echo "📄 Este resumo foi salvo em: /root/install_summary.txt"
    echo ""
}

# ============================================================================
# EXECUÇÃO PRINCIPAL
# ============================================================================

main() {
    clear
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║         YOUTUBE AUDIO EXTRACTOR - INSTALADOR                 ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Este instalador vai configurar o sistema com SUAS credenciais:"
    echo ""
    echo "• Domínio: $DOMAIN_NAME"
    echo "• Banco: $DB_DATABASE"
    echo "• Usuário BD: $DB_USERNAME"
    echo ""
    
    read -p "Pressione Enter para continuar ou Ctrl+C para cancelar..."
    echo ""
    
    # Verificar root
    check_root
    
    # 1. Instalar dependências
    install_dependencies
    
    # 2. Configurar MySQL (com interação simples)
    setup_mysql
    
    # 3. Configurar site
    setup_website
    
    # 4. Configurar SSL (se DNS pronto)
    setup_ssl
    
    # 5. Configurar Python
    setup_python_tools
    
    # 6. Configurar firewall
    setup_firewall
    
    # 7. Mostrar resumo
    show_summary
    
    log "✅ Instalação concluída!"
    echo ""
    echo "Lembre-se: Configure o DNS antes de acessar o sistema!"
    echo "Domínio: $DOMAIN_NAME → IP: 45.140.193.50"
    echo ""
}

# Executar
main
