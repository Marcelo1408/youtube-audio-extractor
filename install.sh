#!/bin/bash
# YouTube Audio Extractor - Instalador Completo
# Versão: 4.1.0 - COM SITE REAL DO ZIP

set -e

# ============================================================================
# CONFIGURAÇÕES DE CORES
# ============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# URL do site real
SITE_ZIP_URL="https://github.com/Marcelo1408/youtube-audio-extractor/raw/18d05c50b5bc8c49d813608941b9d79613fdf611/youtube-audio-extractor.zip"

# ============================================================================
# FUNÇÕES DE ESTILO
# ============================================================================
log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[AVISO]${NC} $1"; }
error() { echo -e "${RED}[ERRO]${NC} $1"; }
success() { echo -e "${GREEN}[✓]${NC} $1"; }
step() { echo -e "${CYAN}[$1]${NC} $2"; }

# ============================================================================
# BANNER INICIAL
# ============================================================================
clear
echo -e "${CYAN}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║                                                          ║"
echo "║     🎵 YOUTUBE AUDIO EXTRACTOR - INSTALADOR              ║"
echo "║           COM SITE REAL (ZIP) - v4.1.0                   ║"
echo "║                                                          ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""

# ============================================================================
# SOLICITAR INFORMAÇÕES DO USUÁRIO
# ============================================================================
echo "📋 POR FAVOR, INFORME OS DADOS PARA INSTALAÇÃO:"
echo ""

# Solicitar domínio
while true; do
    read -p "🌐 Digite o domínio (ex: audioextractor.giize.com): " DOMAIN
    if [ -n "$DOMAIN" ]; then
        break
    else
        warn "O domínio não pode ser vazio!"
    fi
done

# Solicitar email
while true; do
    read -p "📧 Digite o email do administrador: " EMAIL
    if [[ "$EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        break
    else
        warn "Email inválido! Use o formato: usuario@dominio.com"
    fi
done

# ============================================================================
# CONFIGURAÇÕES DO SISTEMA
# ============================================================================
INSTALL_DIR="/var/www/audioextractor"
DB_NAME="youtube_extractor"
DB_USER="audioextrac_usr"
DB_PASS="3GqG!%Yg7i;YsI4Y"

# ============================================================================
# CONFIRMAÇÃO DA INSTALAÇÃO
# ============================================================================
echo ""
echo "📊 RESUMO DA INSTALAÇÃO:"
echo "══════════════════════════════════════════════"
echo "🌐 Domínio:          $DOMAIN"
echo "📧 Email Admin:      $EMAIL"
echo "📁 Diretório:        $INSTALL_DIR"
echo "🗄️  Banco de Dados:  $DB_NAME"
echo "📦 Site:             Baixado do GitHub (ZIP)"
echo ""
echo "🔧 Este instalador vai:"
echo "   1. Instalar Apache, MySQL, PHP, Python"
echo "   2. Criar banco de dados"
echo "   3. Baixar e instalar site real do ZIP"
echo "   4. Configurar domínio $DOMAIN"
echo "══════════════════════════════════════════════"
echo ""

read -p "⏯️  Pressione Enter para continuar ou Ctrl+C para cancelar..."

# ============================================================================
# INSTALAÇÃO PRINCIPAL
# ============================================================================

# PASSO 1: INSTALAR PACOTES
step "1/7" "Instalando pacotes básicos..."
apt update > /dev/null 2>&1
apt install -y apache2 mariadb-server mariadb-client \
              software-properties-common curl wget git \
              python3 python3-pip python3-venv ffmpeg unzip > /dev/null 2>&1
success "Pacotes básicos instalados"

# PHP
step "" "Instalando PHP 8.2..."
add-apt-repository -y ppa:ondrej/php > /dev/null 2>&1
apt update > /dev/null 2>&1
apt install -y php8.2 php8.2-cli php8.2-mysql php8.2-curl \
               php8.2-gd php8.2-mbstring php8.2-xml php8.2-zip \
               php8.2-bcmath libapache2-mod-php8.2 > /dev/null 2>&1
success "PHP 8.2 instalado"

# Ferramentas Python
step "" "Instalando ferramentas Python..."
python3 -m venv /opt/audioenv > /dev/null 2>&1
/opt/audioenv/bin/pip install yt-dlp pydub redis > /dev/null 2>&1
success "Ferramentas Python instaladas"

# PASSO 2: CONFIGURAR MYSQL
step "2/7" "Configurando MySQL..."
systemctl start mariadb > /dev/null 2>&1
systemctl enable mariadb > /dev/null 2>&1

echo ""
info "Configuração do MySQL"
echo "────────────────────────────────────"
echo "Para criar o banco de dados, preciso acessar o MySQL."
echo ""
echo "ESCOLHA UMA OPÇÃO:"
echo "A) Usar 'sudo mysql' (recomendado para Ubuntu)"
echo "B) Usar 'mysql -u root' (sem senha)"
echo "C) Usar 'mysql -u root -p' (com senha)"
echo "D) Já configurei manualmente, pular"
echo ""
read -p "Digite A, B, C ou D: " mysql_option

case $mysql_option in
    A|a)
        MYSQL_CMD="sudo mysql"
        ;;
    B|b)
        MYSQL_CMD="mysql -u root"
        ;;
    C|c)
        MYSQL_CMD="mysql -u root -p"
        ;;
    D|d)
        warn "Pulando criação do banco. Crie manualmente depois."
        MYSQL_CMD=""
        ;;
    *)
        error "Opção inválida. Usando 'sudo mysql' como padrão."
        MYSQL_CMD="sudo mysql"
        ;;
esac

if [ -n "$MYSQL_CMD" ]; then
    info "Criando banco de dados $DB_NAME..."
    
    # Criar arquivo SQL temporário
    SQL_FILE="/tmp/setup_db.sql"
    cat > "$SQL_FILE" <<EOF
-- Criar banco de dados
CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` 
CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- Criar usuário
CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' 
IDENTIFIED BY '$DB_PASS';

-- Conceder privilégios
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* 
TO '$DB_USER'@'localhost';

-- Aplicar mudanças
FLUSH PRIVILEGES;

-- Usar o banco
USE \`$DB_NAME\`;

-- ESTRUTURA DO SEU BANCO AQUI (simplificada)
CREATE TABLE IF NOT EXISTS users (
  id INT AUTO_INCREMENT PRIMARY KEY,
  username VARCHAR(50) NOT NULL UNIQUE,
  email VARCHAR(100) NOT NULL UNIQUE,
  password VARCHAR(255) NOT NULL,
  role ENUM('user','admin','moderator') DEFAULT 'user',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS processes (
  id INT AUTO_INCREMENT PRIMARY KEY,
  user_id INT NOT NULL,
  youtube_url TEXT NOT NULL,
  status ENUM('pending','processing','completed','failed') DEFAULT 'pending',
  file_path VARCHAR(500),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- Inserir admin padrão
INSERT INTO users (username, email, password, role) VALUES
('admin', '$EMAIL', '\$2y\$10\$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'admin')
ON DUPLICATE KEY UPDATE email='$EMAIL';
EOF
    
    # Executar SQL
    if $MYSQL_CMD < "$SQL_FILE" 2>/dev/null; then
        success "Banco de dados criado com sucesso!"
    else
        warn "Não foi possível criar via script."
        warn "Crie manualmente depois:"
        warn "  Banco: $DB_NAME"
        warn "  Usuário: $DB_USER"
        warn "  Senha: $DB_PASS"
    fi
    
    rm -f "$SQL_FILE"
fi

# PASSO 3: BAIXAR E INSTALAR SITE REAL DO ZIP
step "3/7" "Baixando e instalando site real do ZIP..."

# Verificar se o ZIP já existe no diretório atual
if [ -f "youtube-audio-extractor.zip" ]; then
    info "Usando arquivo ZIP local..."
    cp youtube-audio-extractor.zip /tmp/site.zip
    success "Arquivo ZIP local encontrado"
else
    info "Baixando site do GitHub..."
    if wget -q -O /tmp/site.zip "$SITE_ZIP_URL"; then
        success "Site baixado do GitHub com sucesso!"
    else
        error "Falha ao baixar o site do GitHub"
        info "Verificando arquivo ZIP local..."
        
        # Procurar arquivo ZIP em outros locais
        if find . -name "*.zip" -type f | grep -q youtube-audio; then
            ZIP_FILE=$(find . -name "*.zip" -type f | grep youtube-audio | head -1)
            cp "$ZIP_FILE" /tmp/site.zip
            success "Arquivo ZIP encontrado: $ZIP_FILE"
        else
            error "Não foi possível encontrar o arquivo youtube-audio-extractor.zip"
            warn "Será criado um site de teste. Você precisará instalar o site manualmente depois."
        fi
    fi
fi

# PASSO 4: PREPARAR DIRETÓRIO E EXTRAIR SITE
step "4/7" "Preparando diretório do site..."

# Criar diretório do site
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# Limpar diretório se existir conteúdo
rm -rf "$INSTALL_DIR"/* 2>/dev/null || true

# Extrair o site se o ZIP existe
if [ -f "/tmp/site.zip" ]; then
    info "Extraindo site real..."
    if unzip -q /tmp/site.zip -d "$INSTALL_DIR"; then
        success "Site extraído com sucesso!"
        
        # Verificar estrutura extraída
        if [ -d "$INSTALL_DIR/youtube-audio-extractor" ]; then
            # Se extraiu para subdiretório, mover conteúdo
            mv "$INSTALL_DIR/youtube-audio-extractor"/* "$INSTALL_DIR/" 2>/dev/null
            mv "$INSTALL_DIR/youtube-audio-extractor"/.* "$INSTALL_DIR/" 2>/dev/null || true
            rm -rf "$INSTALL_DIR/youtube-audio-extractor"
            success "Estrutura de diretórios organizada"
        fi
        
        # Verificar se o site tem arquivos PHP
        if ls "$INSTALL_DIR"/*.php >/dev/null 2>&1; then
            success "Site PHP detectado!"
            
            # Criar .htaccess se não existir
            if [ ! -f "$INSTALL_DIR/.htaccess" ]; then
                cat > "$INSTALL_DIR/.htaccess" <<EOF
Options -Indexes
RewriteEngine On
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule ^ index.php [L]
EOF
                success ".htaccess criado"
            fi
            
            # Configurar .env se houver exemplo
            if [ -f "$INSTALL_DIR/.env.example" ]; then
                cp "$INSTALL_DIR/.env.example" "$INSTALL_DIR/.env"
                # Atualizar configurações no .env
                sed -i "s|APP_URL=.*|APP_URL=https://$DOMAIN|" "$INSTALL_DIR/.env"
                sed -i "s/DB_DATABASE=.*/DB_DATABASE=$DB_NAME/" "$INSTALL_DIR/.env"
                sed -i "s/DB_USERNAME=.*/DB_USERNAME=$DB_USER/" "$INSTALL_DIR/.env"
                sed -i "s/DB_PASSWORD=.*/DB_PASSWORD=$DB_PASS/" "$INSTALL_DIR/.env"
                success "Arquivo .env configurado"
            fi
            
        else
            warn "Nenhum arquivo PHP encontrado no site extraído"
            create_test_site
        fi
        
    else
        error "Falha ao extrair o ZIP"
        create_test_site
    fi
else
    warn "Nenhum arquivo ZIP disponível. Criando site de teste..."
    create_test_site
fi

# Função para criar site de teste (se necessário)
create_test_site() {
    cat > "$INSTALL_DIR/index.php" <<EOF
<!DOCTYPE html>
<html>
<head>
    <title>YouTube Audio Extractor</title>
    <style>
        body { font-family: Arial; margin: 40px; background: #f5f5f5; }
        .box { background: white; padding: 25px; border-radius: 10px; margin: 25px 0; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        .success { color: #28a745; }
        .error { color: #dc3545; }
        h1 { color: #343a40; }
        .warning { background: #fff3cd; border: 1px solid #ffeaa7; color: #856404; padding: 15px; border-radius: 5px; }
    </style>
</head>
<body>
    <h1>🎵 YouTube Audio Extractor</h1>
    
    <div class="warning">
        <h2>⚠️ SITE REAL NÃO INSTALADO</h2>
        <p>O instalador não conseguiu baixar/extrair o site real.</p>
        <p><strong>Solução:</strong></p>
        <ol>
            <li>Baixe manualmente: <a href="$SITE_ZIP_URL" target="_blank">youtube-audio-extractor.zip</a></li>
            <li>Extraia no diretório: <?php echo __DIR__; ?></li>
            <li>Configure o arquivo .env com as credenciais do banco</li>
        </ol>
    </div>
    
    <div class="box">
        <h2>🧪 Testes do Sistema</h2>
        <?php
        // Testar PHP
        echo '<p class="success">✅ PHP ' . phpversion() . ' funcionando</p>';
        
        // Testar MySQL
        \$conn = new mysqli('localhost', '$DB_USER', '$DB_PASS', '$DB_NAME');
        if (\$conn->connect_error) {
            echo '<p class="error">❌ MySQL: ' . \$conn->connect_error . '</p>';
        } else {
            echo '<p class="success">✅ MySQL conectado ao banco: $DB_NAME</p>';
            \$conn->close();
        }
        
        // Testar Apache
        echo '<p class="success">✅ Apache funcionando</p>';
        
        // Testar Python/yt-dlp
        exec('/opt/audioenv/bin/python3 -c "import yt_dlp; print(\"✅ yt-dlp instalado\")"', \$output, \$return);
        if (\$return === 0) {
            echo '<p class="success">✅ yt-dlp e Python funcionando</p>';
        } else {
            echo '<p class="error">❌ yt-dlp não disponível</p>';
        }
        ?>
    </div>
    
    <div class="box">
        <h2>📊 Informações do Sistema</h2>
        <p><strong>Domínio:</strong> <?php echo \$_SERVER['HTTP_HOST'] ?? '$DOMAIN'; ?></p>
        <p><strong>Diretório:</strong> <?php echo __DIR__; ?></p>
        <p><strong>Email Admin:</strong> <?php echo '$EMAIL'; ?></p>
        <p><strong>Data:</strong> <?php echo date('d/m/Y H:i:s'); ?></p>
    </div>
</body>
</html>
EOF
    success "Site de teste criado"
}

# PASSO 5: CONFIGURAR APACHE
step "5/7" "Configurando Apache..."

# Configurar Virtual Host
cat > /etc/apache2/sites-available/audioextractor.conf <<EOF
<VirtualHost *:80>
    ServerName $DOMAIN
    ServerAdmin $EMAIL
    DocumentRoot $INSTALL_DIR
    
    ErrorLog \${APACHE_LOG_DIR}/audioextractor-error.log
    CustomLog \${APACHE_LOG_DIR}/audioextractor-access.log combined
    
    <Directory $INSTALL_DIR>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    
    # Configurações para processamento de áudio
    php_value upload_max_filesize 2G
    php_value post_max_size 2G
    php_value max_execution_time 600
    php_value memory_limit 1G
    php_value max_input_time 600
    
    # Headers de segurança
    Header always set X-Content-Type-Options "nosniff"
    Header always set X-Frame-Options "SAMEORIGIN"
</VirtualHost>
EOF

# Ativar site
a2dissite 000-default.conf 2>/dev/null || true
a2ensite audioextractor.conf
a2enmod rewrite > /dev/null 2>&1
systemctl restart apache2 > /dev/null 2>&1
success "Apache configurado para $DOMAIN"

# PASSO 6: CONFIGURAR SSL (OPCIONAL)
step "6/7" "Configurando SSL..."
echo ""
info "Para configurar SSL automaticamente, o DNS deve estar apontado."
echo "Domínio: $DOMAIN"
echo "IP do servidor: 45.140.193.50"
echo ""
read -p "🔧 O DNS já está configurado? (s/n): " -n 1 dns_ok
echo ""

if [[ $dns_ok =~ ^[Ss]$ ]]; then
    apt install -y certbot python3-certbot-apache > /dev/null 2>&1
    if certbot --apache -d "$DOMAIN" --non-interactive --agree-tos --email "$EMAIL" > /dev/null 2>&1; then
        success "SSL configurado com sucesso!"
    else
        warn "Falha na configuração do SSL."
        info "Configure manualmente depois:"
        info "  sudo certbot --apache -d $DOMAIN"
    fi
else
    warn "SSL não configurado (DNS não apontado)."
    info "Configure após configurar DNS:"
    info "  sudo certbot --apache -d $DOMAIN"
fi

# PASSO 7: PERMISSÕES E FINALIZAÇÃO
step "7/7" "Configurando permissões e finalizando..."
chown -R www-data:www-data "$INSTALL_DIR" > /dev/null 2>&1
find "$INSTALL_DIR" -type d -exec chmod 755 {} \; > /dev/null 2>&1
find "$INSTALL_DIR" -type f -exec chmod 644 {} \; > /dev/null 2>&1

# Criar diretórios necessários
mkdir -p "$INSTALL_DIR/uploads" "$INSTALL_DIR/temp" "$INSTALL_DIR/logs" 2>/dev/null
chmod 775 "$INSTALL_DIR/uploads" "$INSTALL_DIR/temp" "$INSTALL_DIR/logs" 2>/dev/null
chown www-data:www-data "$INSTALL_DIR/uploads" "$INSTALL_DIR/temp" "$INSTALL_DIR/logs" 2>/dev/null

success "Permissões configuradas"
sleep 2

# ============================================================================
# RESUMO FINAL
# ============================================================================
clear
echo -e "${GREEN}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║                                                          ║"
echo "║          ✅ INSTALAÇÃO CONCLUÍDA COM SUCESSO!            ║"
echo "║                                                          ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""
echo "📊 RESUMO DA INSTALAÇÃO:"
echo "══════════════════════════════════════════════════════════"
echo "🌐 Domínio:          $DOMAIN"
echo "📧 Email Admin:      $EMAIL"
echo "📁 Diretório:        $INSTALL_DIR"
echo ""

if [ -f "/tmp/site.zip" ] && [ -f "$INSTALL_DIR/index.php" ]; then
    echo "✅ Status Site:      Site real instalado do ZIP"
else
    echo "⚠️  Status Site:      Site de teste (instale manualmente)"
fi

echo ""
echo "🗄️  Banco de Dados:"
echo "────────────────────────────────────"
echo "Banco:      $DB_NAME"
echo "Usuário:    $DB_USER"
echo "Senha:      $DB_PASS"
echo ""
echo "🔧 Próximos Passos:"
echo "────────────────────────────────────"

if [ ! -f "/tmp/site.zip" ] || [ ! -f "$INSTALL_DIR/index.php" ]; then
    echo "1. 📦 BAIXE O SITE REAL:"
    echo "   wget '$SITE_ZIP_URL'"
    echo "   unzip youtube-audio-extractor.zip -d $INSTALL_DIR/"
    echo ""
fi

echo "2. 🌐 CONFIGURE O DNS:"
echo "   $DOMAIN → 45.140.193.50"
echo ""
echo "3. 🔒 CONFIGURE SSL (após DNS):"
echo "   sudo certbot --apache -d $DOMAIN"
echo ""
echo "4. 🚀 ACESSE O SISTEMA:"
echo "   http://$DOMAIN (ou https após SSL)"
echo ""
echo "5. 👤 LOGIN ADMIN (padrão):"
echo "   Usuário: admin"
echo "   Email: $EMAIL"
echo "   Senha: admin123 (altere no primeiro acesso)"
echo ""
echo "⚙️  Comandos úteis:"
echo "────────────────────────────────────"
echo "• Reiniciar Apache: sudo systemctl restart apache2"
echo "• Ver logs: sudo tail -f /var/log/apache2/audioextractor-*.log"
echo "• Acessar MySQL: mysql -u $DB_USER -p $DB_NAME"
echo "• Acessar diretório: cd $INSTALL_DIR"
echo "• Ver status: systemctl status apache2 mariadb"
echo "══════════════════════════════════════════════════════════"
echo ""

# Criar arquivo de resumo
cat > /root/instalacao_resumo.txt <<EOF
========================================
YOUTUBE AUDIO EXTRACTOR - RESUMO
========================================
Data: $(date)

SISTEMA
-------
URL: https://$DOMAIN
Diretório: $INSTALL_DIR
Email admin: $EMAIL

BANCO DE DADOS
--------------
Host: localhost
Banco: $DB_NAME
Usuário: $DB_USER
Senha: $DB_PASS

SITE
----
Status: $(if [ -f "/tmp/site.zip" ] && [ -f "$INSTALL_DIR/index.php" ]; then echo "INSTALADO (do ZIP)"; else echo "NÃO INSTALADO - Baixe manualmente"; fi)
Arquivo ZIP: $SITE_ZIP_URL

DNS
---
Domínio: $DOMAIN
IP do servidor: 45.140.193.50

PRÓXIMOS PASSOS
---------------
$(if [ ! -f "/tmp/site.zip" ] || [ ! -f "$INSTALL_DIR/index.php" ]; then echo "1. Baixe o site: wget '$SITE_ZIP_URL'"; echo "2. Extraia: unzip youtube-audio-extractor.zip -d $INSTALL_DIR/"; fi)
$(if [ ! -f "/tmp/site.zip" ] || [ ! -f "$INSTALL_DIR/index.php" ]; then echo "3. "; fi)Configure DNS: $DOMAIN → 45.140.193.50
$(if [ ! -f "/tmp/site.zip" ] || [ ! -f "$INSTALL_DIR/index.php" ]; then echo "4. "; else echo "3. "; fi)Configure SSL: sudo certbot --apache -d $DOMAIN
$(if [ ! -f "/tmp/site.zip" ] || [ ! -f "$INSTALL_DIR/index.php" ]; then echo "5. "; else echo "4. "; fi)Acesse: https://$DOMAIN

COMANDOS
--------
Testar MySQL: mysql -u $DB_USER -p $DB_NAME
Reiniciar Apache: sudo systemctl restart apache2
Ver logs: sudo tail -f /var/log/apache2/audioextractor-*.log
========================================
EOF

success "📄 Resumo salvo em: /root/instalacao_resumo.txt"
echo ""
info "🎉 Instalação concluída!"
if [ -f "/tmp/site.zip" ] && [ -f "$INSTALL_DIR/index.php" ]; then
    info "✅ Site real instalado com sucesso! Acesse: http://$DOMAIN"
else
    info "⚠️  Site não instalado. Baixe e extraia manualmente o ZIP."
fi
echo ""
