-- backend/database/schema.sql
-- Schema do YouTube Audio Extractor Pro

-- Criar banco de dados (será substituído pelo nome escolhido)
CREATE DATABASE IF NOT EXISTS `youtube_audio_extractor` 
CHARACTER SET utf8mb4 
COLLATE utf8mb4_unicode_ci;

USE `youtube_audio_extractor`;

-- Desabilitar foreign keys temporariamente
SET FOREIGN_KEY_CHECKS = 0;

-- Tabela de usuários
CREATE TABLE IF NOT EXISTS users (
    id INT PRIMARY KEY AUTO_INCREMENT,
    google_id VARCHAR(255) UNIQUE,
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
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_email (email),
    INDEX idx_google_id (google_id),
    INDEX idx_role (role),
    INDEX idx_created_at (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Tabela de vídeos processados
CREATE TABLE IF NOT EXISTS videos (
    id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT NOT NULL,
    video_id VARCHAR(100) NOT NULL,
    title VARCHAR(500) NOT NULL,
    description TEXT,
    duration INT NOT NULL,
    url TEXT NOT NULL,
    thumbnail_url TEXT,
    channel_title VARCHAR(255),
    status ENUM('pending', 'processing', 'downloading', 'converting', 'separating', 'completed', 'failed') DEFAULT 'pending',
    quality INT DEFAULT 128,
    separate_tracks BOOLEAN DEFAULT TRUE,
    audio_path TEXT,
    video_path TEXT,
    zip_path TEXT,
    file_size BIGINT,
    error_message TEXT,
    retry_count INT DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    started_at DATETIME,
    completed_at DATETIME,
    deleted_at DATETIME,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    INDEX idx_user_id (user_id),
    INDEX idx_status (status),
    INDEX idx_created_at (created_at),
    INDEX idx_video_id (video_id),
    INDEX idx_status_created (status, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Tabela de faixas de áudio separadas
CREATE TABLE IF NOT EXISTS audio_tracks (
    id INT PRIMARY KEY AUTO_INCREMENT,
    video_id INT NOT NULL,
    name VARCHAR(255) NOT NULL,
    file_path TEXT NOT NULL,
    track_type ENUM('vocals', 'drums', 'bass', 'other', 'full') DEFAULT 'full',
    duration INT,
    file_size BIGINT,
    format VARCHAR(10),
    bitrate INT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (video_id) REFERENCES videos(id) ON DELETE CASCADE,
    INDEX idx_video_id (video_id),
    INDEX idx_track_type (track_type),
    INDEX idx_created_at (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Tabela de logs de atividades
CREATE TABLE IF NOT EXISTS activity_logs (
    id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT NOT NULL,
    activity_type VARCHAR(100) NOT NULL,
    details JSON,
    ip_address VARCHAR(45),
    user_agent TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    INDEX idx_user_id (user_id),
    INDEX idx_activity_type (activity_type),
    INDEX idx_created_at (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Tabela de configurações do sistema
CREATE TABLE IF NOT EXISTS system_settings (
    id INT PRIMARY KEY AUTO_INCREMENT,
    setting_key VARCHAR(100) UNIQUE NOT NULL,
    setting_value TEXT NOT NULL,
    setting_type ENUM('string', 'number', 'boolean', 'json') DEFAULT 'string',
    description TEXT,
    is_public BOOLEAN DEFAULT FALSE,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    updated_by INT,
    INDEX idx_setting_key (setting_key),
    INDEX idx_is_public (is_public)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Tabela de sessões (para session store)
CREATE TABLE IF NOT EXISTS sessions (
    session_id VARCHAR(128) PRIMARY KEY,
    expires TIMESTAMP NOT NULL,
    data TEXT,
    INDEX idx_expires (expires)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Tabela de cache
CREATE TABLE IF NOT EXISTS cache (
    cache_key VARCHAR(255) PRIMARY KEY,
    cache_value LONGTEXT NOT NULL,
    expires_at TIMESTAMP NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_expires_at (expires_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Tabela de fila de processamento
CREATE TABLE IF NOT EXISTS processing_queue (
    id INT PRIMARY KEY AUTO_INCREMENT,
    video_id INT NOT NULL,
    priority INT DEFAULT 1,
    status ENUM('pending', 'processing', 'completed', 'failed') DEFAULT 'pending',
    attempts INT DEFAULT 0,
    max_attempts INT DEFAULT 3,
    error_message TEXT,
    scheduled_for TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    started_at DATETIME,
    completed_at DATETIME,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (video_id) REFERENCES videos(id) ON DELETE CASCADE,
    INDEX idx_status (status),
    INDEX idx_priority (priority),
    INDEX idx_scheduled_for (scheduled_for)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Inserir configurações padrão
INSERT IGNORE INTO system_settings (setting_key, setting_value, setting_type, description, is_public) VALUES
('daily_limit_free', '5', 'number', 'Limite diário de processamentos para usuários free', true),
('daily_limit_premium', '50', 'number', 'Limite diário de processamentos para usuários premium', true),
('max_duration_free', '1800', 'number', 'Duração máxima em segundos para vídeos free (30 minutos)', true),
('max_duration_premium', '7200', 'number', 'Duração máxima em segundos para vídeos premium (2 horas)', true),
('site_name', 'YouTube Audio Extractor Pro', 'string', 'Nome do site', true),
('site_url', 'http://localhost:3000', 'string', 'URL do site', true),
('contact_email', 'suporte@youraudioextractor.com', 'string', 'Email de contato', true),
('allowed_formats', 'mp3,wav,flac,m4a,ogg', 'string', 'Formatos de áudio permitidos', true),
('max_file_size', '104857600', 'number', 'Tamanho máximo de arquivo em bytes (100MB)', true),
('maintenance_mode', 'false', 'boolean', 'Modo de manutenção do sistema', true),
('registration_enabled', 'true', 'boolean', 'Permitir novos cadastros', true),
('google_auth_enabled', 'true', 'boolean', 'Permitir login com Google', true),
('default_audio_quality', '128', 'number', 'Qualidade padrão do áudio (kbps)', false),
('enable_audio_separation', 'true', 'boolean', 'Habilitar separação de áudio', false),
('max_separation_tracks', '5', 'number', 'Máximo de faixas para separação', false),
('keep_videos_days', '7', 'number', 'Dias para manter vídeos processados', false),
('temp_files_lifetime', '24', 'number', 'Horas para manter arquivos temporários', false);

-- Criar usuário admin padrão (senha: Admin123!)
-- Nota: A senha hash deve ser gerada pelo sistema
INSERT IGNORE INTO users (email, username, password_hash, role, email_verified) 
VALUES ('admin@example.com', 'Administrador', '$2a$10$YourHashedPasswordHere', 'admin', TRUE);

-- Criar índices adicionais para performance
CREATE INDEX IF NOT EXISTS idx_videos_completed ON videos(status, completed_at);
CREATE INDEX IF NOT EXISTS idx_videos_user_status ON videos(user_id, status);
CREATE INDEX IF NOT EXISTS idx_users_verification ON users(verification_token, verification_expires);
CREATE INDEX IF NOT EXISTS idx_users_reset ON users(reset_token, reset_expires);
CREATE INDEX IF NOT EXISTS idx_audio_tracks_video_type ON audio_tracks(video_id, track_type);
CREATE INDEX IF NOT EXISTS idx_processing_queue_status ON processing_queue(status, scheduled_for);

-- Habilitar foreign keys novamente
SET FOREIGN_KEY_CHECKS = 1;

-- Procedimento para limpeza de dados antigos
DELIMITER //
CREATE PROCEDURE IF NOT EXISTS cleanup_old_data()
BEGIN
    -- Limpar vídeos com mais de 30 dias
    DELETE FROM videos 
    WHERE created_at < DATE_SUB(NOW(), INTERVAL 30 DAY) 
    AND status = 'completed';
    
    -- Limpar logs de atividade com mais de 90 dias
    DELETE FROM activity_logs 
    WHERE created_at < DATE_SUB(NOW(), INTERVAL 90 DAY);
    
    -- Limpar cache expirado
    DELETE FROM cache 
    WHERE expires_at < NOW();
    
    -- Limpar sessões expiradas
    DELETE FROM sessions 
    WHERE expires < NOW();
END//
DELIMITER ;

-- Evento para limpeza automática diária
CREATE EVENT IF NOT EXISTS daily_cleanup
ON SCHEDULE EVERY 1 DAY
STARTS CURRENT_TIMESTAMP
DO
    CALL cleanup_old_data();

-- Ativar eventos
SET GLOBAL event_scheduler = ON;

-- Trigger para atualizar updated_at
DELIMITER //
CREATE TRIGGER IF NOT EXISTS update_videos_timestamp
BEFORE UPDATE ON videos
FOR EACH ROW
BEGIN
    SET NEW.updated_at = CURRENT_TIMESTAMP;
END//
DELIMITER ;

-- View para estatísticas
CREATE OR REPLACE VIEW user_stats AS
SELECT 
    u.id,
    u.email,
    u.username,
    u.role,
    COUNT(v.id) as total_videos,
    SUM(CASE WHEN v.status = 'completed' THEN 1 ELSE 0 END) as completed_videos,
    SUM(CASE WHEN v.status = 'failed' THEN 1 ELSE 0 END) as failed_videos,
    COALESCE(SUM(v.file_size), 0) as total_storage_used
FROM users u
LEFT JOIN videos v ON u.id = v.user_id
GROUP BY u.id, u.email, u.username, u.role;
