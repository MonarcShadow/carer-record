-- ============================================================
--  Carer Record — Schema principal MariaDB
--  Ejecutar en la Raspberry Pi:
--    mysql -u root -p < init_db.sql
-- ============================================================

CREATE DATABASE IF NOT EXISTS carer_record
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

USE carer_record;

-- ------------------------------------------------------------
-- Usuarios / Personal clínico
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS users (
    id           VARCHAR(36)  PRIMARY KEY,
    name         VARCHAR(200) NOT NULL,
    email        VARCHAR(200) NOT NULL UNIQUE,
    role         ENUM('nurse','doctor','admin','tech') NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    active       BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at   TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- ------------------------------------------------------------
-- Pacientes (modelo interno normalizado)
-- Todos los adaptadores (FHIR, HL7v2, etc.) mapean aquí.
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS patients (
    id                      VARCHAR(36)  PRIMARY KEY,
    -- ID en el sistema origen (FHIR resource ID, HL7v2 PID-3, etc.)
    external_id             VARCHAR(100),
    source_system           ENUM('fhir','hl7v2','csv','manual') NOT NULL,
    first_name              VARCHAR(100),
    last_name               VARCHAR(100),
    birth_date              DATE,
    gender                  ENUM('male','female','other','unknown') DEFAULT 'unknown',
    -- Identificador local (RUT u otro documento)
    local_id                VARCHAR(500),
    -- Ubicación actual
    ward                    VARCHAR(100),   -- Ej: "UCI", "Pediatría"
    bed_number              VARCHAR(20),
    admission_date          DATETIME,
    expected_discharge_date DATE,
    -- Diagnóstico principal de ingreso (texto libre)
    primary_diagnosis       TEXT,
    active                  BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at              TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at              TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP
                                         ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_external       (external_id, source_system),
    INDEX idx_active_ward    (active, ward)
) ENGINE=InnoDB;

-- ------------------------------------------------------------
-- Notas de turno
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS notes (
    id           VARCHAR(36)  PRIMARY KEY,
    patient_id   VARCHAR(36)  NOT NULL,
    author_id    VARCHAR(36)  NOT NULL,
    content      TEXT         NOT NULL,
    input_method ENUM('text','voice') NOT NULL DEFAULT 'text',
    -- NULL = pendiente de sync desde el dispositivo
    synced_at    TIMESTAMP    NULL,
    created_at   TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (patient_id) REFERENCES patients(id) ON DELETE CASCADE,
    FOREIGN KEY (author_id)  REFERENCES users(id),
    INDEX idx_patient_time   (patient_id, created_at DESC)
) ENGINE=InnoDB;

-- ------------------------------------------------------------
-- Cambios de turno
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS shift_changes (
    id               VARCHAR(36) PRIMARY KEY,
    patient_id       VARCHAR(36) NOT NULL,
    outgoing_user_id VARCHAR(36),
    incoming_user_id VARCHAR(36),
    -- Resumen generado durante el cambio de turno
    summary          TEXT,
    created_at       TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (patient_id)       REFERENCES patients(id) ON DELETE CASCADE,
    FOREIGN KEY (outgoing_user_id) REFERENCES users(id),
    FOREIGN KEY (incoming_user_id) REFERENCES users(id)
) ENGINE=InnoDB;

-- ------------------------------------------------------------
-- Mensajes HL7v2 crudos (staging + auditoría)
-- El adaptador HL7v2 escribe aquí primero, luego normaliza.
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS hl7v2_raw_messages (
    id           VARCHAR(36)  PRIMARY KEY,
    message_type VARCHAR(20)  NOT NULL,  -- Ej: 'ADT^A01', 'ORU^R01'
    raw_message  MEDIUMTEXT   NOT NULL,
    processed    BOOLEAN      NOT NULL DEFAULT FALSE,
    -- Rellenado después de normalizar
    patient_id   VARCHAR(36)  NULL,
    error_detail TEXT         NULL,
    received_at  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (patient_id) REFERENCES patients(id),
    INDEX idx_unprocessed (processed, received_at)
) ENGINE=InnoDB;

-- ------------------------------------------------------------
-- Log de sincronización FHIR
-- Rastrea qué bundles/recursos ya fueron importados.
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS fhir_sync_log (
    id            VARCHAR(36)  PRIMARY KEY,
    resource_type VARCHAR(50)  NOT NULL,  -- 'Patient', 'Encounter', etc.
    resource_id   VARCHAR(100) NOT NULL,
    bundle_file   VARCHAR(255),
    status        ENUM('success','error','skipped') NOT NULL,
    error_detail  TEXT         NULL,
    imported_at   TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_resource (resource_type, resource_id)
) ENGINE=InnoDB;

-- ------------------------------------------------------------
-- Usuario de prueba (cambiar contraseña en producción)
-- password = 'admin123' hasheado con bcrypt
-- ------------------------------------------------------------
INSERT IGNORE INTO users (id, name, email, role, password_hash) VALUES
(UUID(), 'Admin Sistema', 'admin@hospital.cl', 'admin',
 '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewdBpj2PgCf2Cxbe');
USE carer_record;

-- ------------------------------------------------------------
-- Encuentros / Hospitalizaciones
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS encounters (
    id              VARCHAR(36)  PRIMARY KEY,
    patient_id      VARCHAR(36)  NOT NULL,
    external_id     VARCHAR(100),
    source_system   ENUM('fhir','hl7v2','manual') NOT NULL DEFAULT 'fhir',
    encounter_type  VARCHAR(100),
    status          VARCHAR(50),
    start_date      DATETIME,
    end_date        DATETIME,
    reason          TEXT,
    created_at      TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (patient_id) REFERENCES patients(id) ON DELETE CASCADE,
    INDEX idx_patient (patient_id),
    INDEX idx_external (external_id)
) ENGINE=InnoDB;

-- ------------------------------------------------------------
-- Condiciones / Diagnósticos
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS conditions (
    id              VARCHAR(36)  PRIMARY KEY,
    patient_id      VARCHAR(36)  NOT NULL,
    external_id     VARCHAR(100),
    code            VARCHAR(50),
    code_system     VARCHAR(100),
    description     TEXT,
    status          VARCHAR(50)  DEFAULT 'active',
    onset_date      DATE,
    abatement_date  DATE,
    created_at      TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (patient_id) REFERENCES patients(id) ON DELETE CASCADE,
    INDEX idx_patient (patient_id),
    INDEX idx_status  (patient_id, status)
) ENGINE=InnoDB;

-- ------------------------------------------------------------
-- Medicamentos activos
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS medications (
    id              VARCHAR(36)  PRIMARY KEY,
    patient_id      VARCHAR(36)  NOT NULL,
    external_id     VARCHAR(100),
    code            VARCHAR(50),
    code_system     VARCHAR(100),
    description     TEXT,
    dosage          VARCHAR(200),
    frequency       VARCHAR(100),
    status          VARCHAR(50)  DEFAULT 'active',
    start_date      DATE,
    end_date        DATE,
    created_at      TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (patient_id) REFERENCES patients(id) ON DELETE CASCADE,
    INDEX idx_patient (patient_id),
    INDEX idx_status  (patient_id, status)
) ENGINE=InnoDB;

-- ------------------------------------------------------------
-- Observaciones / Signos vitales y laboratorio
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS observations (
    id              VARCHAR(36)  PRIMARY KEY,
    patient_id      VARCHAR(36)  NOT NULL,
    external_id     VARCHAR(100),
    code            VARCHAR(50),
    code_system     VARCHAR(100),
    description     VARCHAR(200),
    value           VARCHAR(200),
    unit            VARCHAR(50),
    status          VARCHAR(50),
    effective_date  DATETIME,
    created_at      TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (patient_id) REFERENCES patients(id) ON DELETE CASCADE,
    INDEX idx_patient      (patient_id),
    INDEX idx_patient_date (patient_id, effective_date DESC)
) ENGINE=InnoDB;

-- ------------------------------------------------------------
-- Alergias
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS allergies (
    id              VARCHAR(36)  PRIMARY KEY,
    patient_id      VARCHAR(36)  NOT NULL,
    external_id     VARCHAR(100),
    code            VARCHAR(50),
    code_system     VARCHAR(100),
    description     TEXT,
    severity        VARCHAR(50),
    status          VARCHAR(50)  DEFAULT 'active',
    onset_date      DATE,
    created_at      TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (patient_id) REFERENCES patients(id) ON DELETE CASCADE,
    INDEX idx_patient (patient_id)
) ENGINE=InnoDB;
