#!/bin/bash
# YouTube Audio Extractor - Instalador Ultra Simples
# Versão: 4.0.0

set -e

# ============================================================================
# CONFIGURAÇÕES (FIXAS - SEU SISTEMA)
# ============================================================================
DOMAIN="audioextractor.giize.com"
EMAIL="mpnascimento031@gmail.com"
INSTALL_DIR="/var/www/audioextractor"
DB_NAME="youtube_extractor"
DB_USER="audioextrac_usr"
DB_PASS="3GqG!%Yg7i;YsI4Y"

# ============================================================================
# FUNÇÕES SIMPLES
# ============================================================================
green() { echo -e "\033[1;32m$1\033[0m"; }
blue() { echo -e "\033[1;34m$1\033[0m"; }
yellow() { echo -e "\033[1;33m$1\033[0m"; }
red() { echo -e "\033[1;31m$1\033[0m"; }

# ============================================================================
# INSTALAÇÃO PRINCIPAL
# ============================================================================
clear
echo "================================================"
echo "    YOUTUBE AUDIO EXTRACTOR - INSTALADOR"
echo "================================================"
echo ""
echo "Este instalador vai:"
echo "1. Instalar Apache, MySQL, PHP, Python"
echo "2. Criar banco de dados: $DB_NAME"
echo "3. Configurar site em: $INSTALL_DIR"
echo "4. Configurar domínio: $DOMAIN"
echo ""
read -p "Pressione Enter para continuar ou Ctrl+C para cancelar..."

# ============================================================================
# PASSO 1: INSTALAR PACOTES
# ============================================================================
blue "\n[1/6] Instalando pacotes básicos..."
apt update
apt install -y apache2 mariadb-server mariadb-client \
              software-properties-common curl wget git \
              python3 python3-pip python3-venv ffmpeg

# PHP
add-apt-repository -y ppa:ondrej/php
apt update
apt install -y php8.2 php8.2-cli php8.2-mysql php8.2-curl \
               php8.2-gd php8.2-mbstring php8.2-xml php8.2-zip \
               php8.2-bcmath libapache2-mod-php8.2

# Ferramentas Python
blue "\n[2/6] Instalando ferramentas Python..."
python3 -m venv /opt/audioenv
/opt/audioenv/bin/pip install yt-dlp pydub redis

# ============================================================================
# PASSO 2: CONFIGURAR MYSQL
# ============================================================================
blue "\n[3/6] Configurando MySQL..."
systemctl start mariadb
systemctl enable mariadb

echo ""
echo "================================================"
echo "        CONFIGURAÇÃO DO MYSQL"
echo "================================================"
echo ""
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
        yellow "Pulando criação do banco. Crie manualmente depois."
        MYSQL_CMD=""
        ;;
    *)
        red "Opção inválida. Usando 'sudo mysql' como padrão."
        MYSQL_CMD="sudo mysql"
        ;;
esac

if [ -n "$MYSQL_CMD" ]; then
    blue "Criando banco de dados $DB_NAME..."
    
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
        green "✅ Banco de dados criado com sucesso!"
    else
        yellow "⚠️  Não foi possível criar via script."
        yellow "Crie manualmente depois:"
        yellow "  Banco: $DB_NAME"
        yellow "  Usuário: $DB_USER"
        yellow "  Senha: $DB_PASS"
    fi
    
    rm -f "$SQL_FILE"
fi

# ============================================================================
# PASSO 3: CONFIGURAR APACHE
# ============================================================================
blue "\n[4/6] Configurando Apache..."

# Criar diretório do site
mkdir -p "$INSTALL_DIR"

# Criar index.php de teste
cat > "$INSTALL_DIR/index.php" <<EOF
<!DOCTYPE html>
<html>
<head>
    <title>YouTube Audio Extractor</title>
    <style>
        body { font-family: Arial; margin: 40px; }
        .box { background: #f0f0f0; padding: 20px; border-radius: 5px; margin: 20px 0; }
        .success { color: green; }
        .error { color: red; }
    </style>
</head>
<body>
    <h1>🎵 YouTube Audio Extractor</h1>
    
    <div class="box">
        <h2>✅ Sistema Instalado</h2>
        <p><strong>Domínio:</strong> <?php echo \$_SERVER['HTTP_HOST'] ?? '$DOMAIN'; ?></p>
        <p><strong>Diretório:</strong> <?php echo __DIR__; ?></p>
        <p><strong>Data:</strong> <?php echo date('d/m/Y H:i:s'); ?></p>
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
        ?>
    </div>
    
    <div class="box">
        <h2>📁 Próximos Passos</h2>
        <ol>
            <li>Copie seus arquivos PHP para: <?php echo __DIR__; ?></li>
            <li>Configure o arquivo .env com suas credenciais</li>
            <li>Configure o DNS: $DOMAIN → 45.140.193.50</li>
            <li>Execute: sudo certbot --apache -d $DOMAIN</li>
        </ol>
    </div>
</body>
</html>
EOF

# Criar .htaccess
cat > "$INSTALL_DIR/.htaccess" <<EOF
Options -Indexes
RewriteEngine On
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule ^ index.php [L]
EOF

# Criar arquivo .env de exemplo
cat > "$INSTALL_DIR/.env.example" <<EOF
APP_NAME=YouTube Audio Extractor
APP_ENV=production
APP_DEBUG=false
APP_URL=https://$DOMAIN

DB_CONNECTION=mysql
DB_HOST=localhost
DB_PORT=3306
DB_DATABASE=$DB_NAME
DB_USERNAME=$DB_USER
DB_PASSWORD=$DB_PASS

CACHE_DRIVER=file
SESSION_DRIVER=file
EOF

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
    
    php_value upload_max_filesize 2G
    php_value post_max_size 2G
    php_value max_execution_time 600
    php_value memory_limit 1G
</VirtualHost>
EOF

# Ativar site
a2dissite 000-default.conf 2>/dev/null || true
a2ensite audioextractor.conf
systemctl restart apache2

# ============================================================================
# PASSO 4: CONFIGURAR SSL (OPCIONAL)
# ============================================================================
blue "\n[5/6] Configurando SSL..."
echo ""
echo "Para configurar SSL automaticamente, o DNS deve estar apontado."
echo "Domínio: $DOMAIN"
echo "IP: 45.140.193.50"
echo ""
read -p "O DNS já está configurado? (s/n): " -n 1 dns_ok
echo ""

if [[ $dns_ok =~ ^[Ss]$ ]]; then
    apt install -y certbot python3-certbot-apache
    if certbot --apache -d "$DOMAIN" --non-interactive --agree-tos --email "$EMAIL"; then
        green "✅ SSL configurado!"
    else
        yellow "⚠️  Falha no SSL. Configure depois:"
        yellow "  sudo certbot --apache -d $DOMAIN"
    fi
else
    yellow "⚠️  SSL não configurado. Configure após DNS:"
    yellow "  sudo certbot --apache -d $DOMAIN"
fi

# ============================================================================
# PASSO 5: PERMISSÕES
# ============================================================================
blue "\n[6/6] Configurando permissões..."
chown -R www-data:www-data "$INSTALL_DIR"
find "$INSTALL_DIR" -type d -exec chmod 755 {} \;
find "$INSTALL_DIR" -type f -exec chmod 644 {} \;

# ============================================================================
# RESUMO FINAL
# ============================================================================
clear
green "================================================"
green "    ✅ INSTALAÇÃO CONCLUÍDA!"
green "================================================"
echo ""
blue "📋 RESUMO:"
echo "----------------------------------------"
echo "🌐 Domínio:      $DOMAIN"
echo "📁 Diretório:    $INSTALL_DIR"
echo "📧 Email:        $EMAIL"
echo ""
echo "🗄️  Banco de Dados:"
echo "----------------------------------------"
echo "Banco:      $DB_NAME"
echo "Usuário:    $DB_USER"
echo "Senha:      $DB_PASS"
echo ""
echo "🔧 Próximos Passos:"
echo "----------------------------------------"
echo "1. COPIE SEUS ARQUIVOS:"
echo "   cp -r /caminho/dos/seus/arquivos/* $INSTALL_DIR/"
echo ""
echo "2. CONFIGURE O DNS:"
echo "   $DOMAIN → 45.140.193.50"
echo ""
echo "3. CONFIGURE SSL (após DNS):"
echo "   sudo certbot --apache -d $DOMAIN"
echo ""
echo "4. ACESSE O SISTEMA:"
echo "   https://$DOMAIN"
echo ""
echo "5. LOGIN ADMIN (padrão):"
echo "   Usuário: admin"
echo "   Email: $EMAIL"
echo ""
blue "⚙️  Comandos úteis:"
echo "----------------------------------------"
echo "• Reiniciar Apache: sudo systemctl restart apache2"
echo "• Ver logs: sudo tail -f /var/log/apache2/audioextractor-*.log"
echo "• Acessar MySQL: mysql -u $DB_USER -p $DB_NAME"
echo "• Acessar diretório: cd $INSTALL_DIR"
echo ""
green "✅ Instalação completa!"
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

DNS
---
Domínio: $DOMAIN
IP do servidor: 45.140.193.50

PRÓXIMOS PASSOS
---------------
1. Copie seus arquivos PHP para $INSTALL_DIR
2. Configure DNS: $DOMAIN → 45.140.193.50
3. Configure SSL: sudo certbot --apache -d $DOMAIN
4. Acesse: https://$DOMAIN

COMANDOS
--------
Testar MySQL: mysql -u $DB_USER -p $DB_NAME
Reiniciar Apache: sudo systemctl restart apache2
Ver logs: sudo tail -f /var/log/apache2/audioextractor-*.log
========================================
EOF

green "📄 Resumo salvo em: /root/instalacao_resumo.txt"
echo ""
