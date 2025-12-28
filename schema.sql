-- schema.sql - 100% compatível com MariaDB/MySQL
-- ATUALIZADO: Cria usuário e concede permissões

-- ============================================
-- 1. CRIAR BANCO DE DADOS
-- ============================================
CREATE DATABASE IF NOT EXISTS youtube_audio_extractor;
USE youtube_audio_extractor;

-- ============================================
-- 2. CRIAR USUÁRIO ESPECÍFICO (do seu .env)
-- ============================================
-- Nota: Esta parte só funciona se executada com privilégios de root
-- Remova se já tiver criado o usuário manualmente

DROP USER IF EXISTS 'youtube_audio_extractor_user'@'localhost';
CREATE USER 'youtube_audio_extractor_user'@'localhost' IDENTIFIED BY '12Marcelo34#';
GRANT ALL PRIVILEGES ON youtube_audio_extractor.* TO 'youtube_audio_extractor_user'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE, CREATE TEMPORARY TABLES ON youtube_audio_extractor.* TO 'youtube_audio_extractor_user'@'localhost';
FLUSH PRIVILEGES;

-- ============================================
-- 3. TABELAS DO SISTEMA
-- ============================================

-- Tabela de usuários
CREATE TABLE IF NOT EXISTS users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    google_id VARCHAR(255),
    email VARCHAR(255) UNIQUE NOT NULL,
    username VARCHAR(100) NOT NULL,
    password_hash VARCHAR(255),
    phone VARCHAR(20),
    role ENUM('free', 'premium', 'admin') DEFAULT 'free',
    email_verified BOOLEAN DEFAULT FALSE,
    verification_token VARCHAR(255),
    verification_expires DATETIME,
    reset_token VARCHAR(255),
    reset_expires DATETIME,
    last_login DATETIME,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- Índices para users
CREATE INDEX idx_email ON users(email);
CREATE INDEX idx_google_id ON users(google_id);
CREATE INDEX idx_role ON users(role);

-- Tabela de vídeos processados
CREATE TABLE IF NOT EXISTS videos (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    video_id VARCHAR(100) NOT NULL,
    title VARCHAR(500) NOT NULL,
    duration INT NOT NULL,
    url TEXT NOT NULL,
    status ENUM('pending', 'processing', 'completed', 'failed') DEFAULT 'pending',
    quality INT DEFAULT 128,
    audio_path TEXT,
    error_message TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    completed_at DATETIME,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- Índices para videos
CREATE INDEX idx_user_id ON videos(user_id);
CREATE INDEX idx_status ON videos(status);
CREATE INDEX idx_created_at ON videos(created_at);

-- Tabela de faixas de áudio
CREATE TABLE IF NOT EXISTS audio_tracks (
    id INT AUTO_INCREMENT PRIMARY KEY,
    video_id INT NOT NULL,
    name VARCHAR(255) NOT NULL,
    file_path TEXT NOT NULL,
    track_type VARCHAR(50),
    file_size BIGINT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (video_id) REFERENCES videos(id) ON DELETE CASCADE
);

CREATE INDEX idx_video_id ON audio_tracks(video_id);

-- Tabela de logs
CREATE TABLE IF NOT EXISTS activity_logs (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    activity_type VARCHAR(100) NOT NULL,
    details TEXT,
    ip_address VARCHAR(45),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX idx_user_activity ON activity_logs(user_id);

-- Tabela de configurações
CREATE TABLE IF NOT EXISTS system_settings (
    id INT AUTO_INCREMENT PRIMARY KEY,
    setting_key VARCHAR(100) UNIQUE NOT NULL,
    setting_value TEXT NOT NULL,
    description TEXT,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

CREATE INDEX idx_setting_key ON system_settings(setting_key);

-- Tabela de sessões
CREATE TABLE IF NOT EXISTS sessions (
    session_id VARCHAR(128) PRIMARY KEY,
    expires TIMESTAMP NOT NULL,
    data TEXT
);

CREATE INDEX idx_expires ON sessions(expires);

-- ============================================
-- 4. DADOS INICIAIS
-- ============================================

-- Inserir configurações padrão
INSERT IGNORE INTO system_settings (setting_key, setting_value, description) VALUES
('daily_limit_free', '5', 'Limite diário para usuários free'),
('daily_limit_premium', '50', 'Limite diário para usuários premium'),
('max_duration_free', '1800', 'Duração máxima para free (30min)'),
('max_duration_premium', '7200', 'Duração máxima para premium (2h)'),
('site_name', 'YouTube Audio Extractor', 'Nome do site'),
('max_file_size', '104857600', 'Tamanho máximo de arquivo (100MB)');

-- Usuário admin padrão (senha: admin123)
-- Usando IGNORE para não dar erro se já existir
INSERT IGNORE INTO users (email, username, password_hash, role, email_verified) 
VALUES ('admin@example.com', 'Admin', '$2a$10$N9qo8uLOickgx2ZMRZoMye.CHx6p5p7Z1F6lB6JtHcQeJ7kTQQF7K', 'admin', TRUE);

-- ============================================
-- 5. CONFIGURAÇÕES ADICIONAIS
-- ============================================

-- Configuração para melhor performance
SET GLOBAL innodb_buffer_pool_size = 134217728; -- 128MB para MariaDB
SET GLOBAL max_connections = 100;
SET GLOBAL connect_timeout = 60;

-- ============================================
-- 6. VERIFICAÇÃO FINAL
-- ============================================
SELECT '✅ Banco de dados criado com sucesso!' as Status;

-- Verificar tabelas criadas
SHOW TABLES;

-- Verificar usuário criado
SELECT user, host FROM mysql.user WHERE user = 'youtube_audio_extractor_user';

-- Verificar permissões
SHOW GRANTS FOR 'youtube_audio_extractor_user'@'localhost';
