-- ============================================================================
-- INSTITUCIÓN UNIVERSITARIA PASCUAL BRAVO
-- Departamento de Sistemas Digitales · Bases de Datos I · Grupo 811
-- Taller 6 · SolarDB: Base de Datos para la Telemetría de una Microrred Híbrida
-- Línea 5: SolarDB: Funciones, Procedimientos y Triggers en PL/pgSQL
--          para Alarmas y Auditoría
-- ============================================================================
-- Archivo: sql/01_esquema_ddl.sql
-- Propósito: Definición del esquema DDL completo (esquemas, dominios, tablas,
--            claves primarias, foráneas, restricciones UNIQUE/CHECK y comentarios).
-- Ejecutar conectado a la base de datos "solardb".
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. CREACIÓN DE ESQUEMAS MODULARES
-- ----------------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS microrred;
CREATE SCHEMA IF NOT EXISTS telemetria;
CREATE SCHEMA IF NOT EXISTS operacion;
CREATE SCHEMA IF NOT EXISTS auditoria;

COMMENT ON SCHEMA microrred IS 'Infraestructura física, componentes y catálogo de equipos de la microrred híbrida.';
COMMENT ON SCHEMA telemetria IS 'Series de tiempo de lecturas eléctricas analógicas de inversores, baterías y red.';
COMMENT ON SCHEMA operacion IS 'Registros de contexto, eventos, catálogo de tipos de alarma y configuración de umbrales.';
COMMENT ON SCHEMA auditoria IS 'Trazabilidad inmutable de cambios (Change Data Capture) en tablas críticas.';

-- ----------------------------------------------------------------------------
-- 2. DOMINIOS Y ENUMERACIONES
-- ----------------------------------------------------------------------------
-- Dominio para niveles de severidad de alarmas
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'nivel_severidad') THEN
        CREATE TYPE operacion.nivel_severidad AS ENUM ('INFO', 'WARNING', 'CRITICAL');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'estado_alarma') THEN
        CREATE TYPE operacion.estado_alarma AS ENUM ('ACTIVA', 'EN_REVISION', 'RESUELTA', 'DESCARTADA');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'accion_auditoria') THEN
        CREATE TYPE auditoria.accion_auditoria AS ENUM ('INSERT', 'UPDATE', 'DELETE');
    END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 3. TABLAS DEL ESQUEMA "microrred" (INFRAESTRUCTURA FÍSICA)
-- ----------------------------------------------------------------------------

-- 3.1 Sitios de instalación (Campus)
CREATE TABLE IF NOT EXISTS microrred.sitios (
    id SERIAL PRIMARY KEY,
    codigo VARCHAR(20) NOT NULL UNIQUE,
    nombre VARCHAR(100) NOT NULL,
    institucion VARCHAR(150) NOT NULL DEFAULT 'CUHK-Shenzhen',
    ciudad VARCHAR(100) NOT NULL,
    pais VARCHAR(50) NOT NULL DEFAULT 'China',
    latitud NUMERIC(9,6) NOT NULL,
    longitud NUMERIC(9,6) NOT NULL,
    altitud_msnm NUMERIC(6,2),
    zona_horaria VARCHAR(50) NOT NULL DEFAULT 'Asia/Shanghai',
    fecha_creacion TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_sitio_latitud CHECK (latitud BETWEEN -90 AND 90),
    CONSTRAINT chk_sitio_longitud CHECK (longitud BETWEEN -180 AND 180)
);

COMMENT ON TABLE microrred.sitios IS 'Campus universitario o locación física donde opera la microrred.';

-- 3.2 Fabricantes de equipos
CREATE TABLE IF NOT EXISTS microrred.fabricantes (
    id SERIAL PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL UNIQUE,
    pais_origen VARCHAR(50),
    contacto_soporte VARCHAR(150),
    sitio_web VARCHAR(255)
);

COMMENT ON TABLE microrred.fabricantes IS 'Fabricantes y proveedores industriales de inversores, baterías y paneles.';

-- 3.3 Modelos de inversores híbridos
CREATE TABLE IF NOT EXISTS microrred.modelos_inversor (
    id SERIAL PRIMARY KEY,
    fabricante_id INT NOT NULL,
    codigo_modelo VARCHAR(50) NOT NULL UNIQUE,
    tipo VARCHAR(50) NOT NULL DEFAULT 'Inversor Híbrido Bidireccional',
    potencia_nominal_va NUMERIC(10,2) NOT NULL DEFAULT 8000.00,
    potencia_nominal_w NUMERIC(10,2) NOT NULL DEFAULT 8000.00,
    tension_nominal_ac_v NUMERIC(6,2) NOT NULL DEFAULT 220.00,
    frecuencia_nominal_hz NUMERIC(4,2) NOT NULL DEFAULT 50.00,
    tension_bateria_dc_v NUMERIC(5,2) NOT NULL DEFAULT 51.20,
    corriente_max_carga_a NUMERIC(6,2) NOT NULL DEFAULT 150.00,
    corriente_max_descarga_a NUMERIC(6,2) NOT NULL DEFAULT 150.00,
    CONSTRAINT fk_modelo_fabricante FOREIGN KEY (fabricante_id)
        REFERENCES microrred.fabricantes (id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT chk_modelo_potencia CHECK (potencia_nominal_w > 0)
);

COMMENT ON TABLE microrred.modelos_inversor IS 'Ficha técnica y especificaciones de fábrica del inversor híbrido.';

-- 3.4 Subsistemas funcionales independientes
CREATE TABLE IF NOT EXISTS microrred.subsistemas (
    id SERIAL PRIMARY KEY,
    sitio_id INT NOT NULL,
    codigo VARCHAR(20) NOT NULL UNIQUE,
    nombre VARCHAR(100) NOT NULL,
    descripcion TEXT,
    tipo_carga_principal VARCHAR(100) NOT NULL,
    fecha_puesta_marcha DATE NOT NULL,
    activo BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT fk_subsistema_sitio FOREIGN KEY (sitio_id)
        REFERENCES microrred.sitios (id)
        ON DELETE RESTRICT ON UPDATE CASCADE
);

COMMENT ON TABLE microrred.subsistemas IS 'Subsistemas físicos independientes de la microrred (1: Cómputo GPU/CPU, 2: Climatización HVAC).';

-- 3.5 Inversores instalados (Instancias físicas)
CREATE TABLE IF NOT EXISTS microrred.inversores (
    id INT PRIMARY KEY, -- Coincide con el Inverter ID lógico del dataset (1 y 2)
    subsistema_id INT NOT NULL UNIQUE,
    modelo_id INT NOT NULL,
    numero_serie VARCHAR(100) NOT NULL UNIQUE,
    direccion_modbus INT NOT NULL DEFAULT 1,
    protocolo_version VARCHAR(20) NOT NULL DEFAULT 'V1.0',
    firmware_version VARCHAR(50) NOT NULL DEFAULT 'HW:M1-S1 FW:1.0',
    descripcion_ubicacion VARCHAR(150),
    activo BOOLEAN NOT NULL DEFAULT TRUE,
    fecha_instalacion DATE NOT NULL,
    CONSTRAINT fk_inversor_subsistema FOREIGN KEY (subsistema_id)
        REFERENCES microrred.subsistemas (id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_inversor_modelo FOREIGN KEY (modelo_id)
        REFERENCES microrred.modelos_inversor (id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT chk_inversor_id CHECK (id IN (1, 2)),
    CONSTRAINT chk_inversor_modbus CHECK (direccion_modbus > 0)
);

COMMENT ON TABLE microrred.inversores IS 'Inversores híbridos activos leídos por telemetría Modbus/RS485.';

-- 3.6 Bancos de baterías de litio (LiFePO4)
CREATE TABLE IF NOT EXISTS microrred.bancos_bateria (
    id SERIAL PRIMARY KEY,
    inversor_id INT NOT NULL UNIQUE,
    quimica VARCHAR(50) NOT NULL DEFAULT 'LiFePO4 (Fosfato de Hierro y Litio)',
    capacidad_nominal_ah NUMERIC(7,2) NOT NULL DEFAULT 200.00,
    tension_nominal_v NUMERIC(5,2) NOT NULL DEFAULT 51.20,
    energia_nominal_kwh NUMERIC(6,2) GENERATED ALWAYS AS (ROUND((capacidad_nominal_ah * tension_nominal_v) / 1000.0, 2)) STORED,
    tension_corte_descarga_v NUMERIC(5,2) NOT NULL DEFAULT 44.00,
    tension_flotacion_v NUMERIC(5,2) NOT NULL DEFAULT 54.00,
    tension_absorcion_v NUMERIC(5,2) NOT NULL DEFAULT 56.40,
    tension_maxima_proteccion_v NUMERIC(5,2) NOT NULL DEFAULT 58.40,
    soc_minimo_recomendado_pct INT NOT NULL DEFAULT 20,
    soc_critico_pct INT NOT NULL DEFAULT 10,
    CONSTRAINT fk_bateria_inversor FOREIGN KEY (inversor_id)
        REFERENCES microrred.inversores (id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT chk_bateria_capacidad CHECK (capacidad_nominal_ah > 0),
    CONSTRAINT chk_bateria_soc_limites CHECK (soc_critico_pct < soc_minimo_recomendado_pct AND soc_minimo_recomendado_pct <= 50)
);

COMMENT ON TABLE microrred.bancos_bateria IS 'Bancos de almacenamiento electroquímico acoplados a cada inversor.';

-- 3.7 Arreglos solares fotovoltaicos (PV Arrays)
CREATE TABLE IF NOT EXISTS microrred.arreglos_solares (
    id SERIAL PRIMARY KEY,
    inversor_id INT NOT NULL UNIQUE,
    numero_paneles INT NOT NULL DEFAULT 26,
    potencia_panel_wp NUMERIC(6,2) NOT NULL DEFAULT 480.00,
    potencia_pico_total_kwp NUMERIC(6,2) GENERATED ALWAYS AS (ROUND((numero_paneles * potencia_panel_wp) / 1000.0, 2)) STORED,
    tecnologia VARCHAR(50) NOT NULL DEFAULT 'Monocristalino PERC',
    azimut_grados NUMERIC(5,2) NOT NULL DEFAULT 180.00, -- Orientación al sur
    inclinacion_grados NUMERIC(4,2) NOT NULL DEFAULT 22.00,
    voc_stc_v NUMERIC(6,2) NOT NULL DEFAULT 49.50,
    isc_stc_a NUMERIC(6,2) NOT NULL DEFAULT 11.80,
    CONSTRAINT fk_pv_inversor FOREIGN KEY (inversor_id)
        REFERENCES microrred.inversores (id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT chk_pv_paneles CHECK (numero_paneles > 0)
);

COMMENT ON TABLE microrred.arreglos_solares IS 'Arreglo fotovoltaico conectado a cada canal MPPT del inversor.';

-- ----------------------------------------------------------------------------
-- 4. TABLAS DEL ESQUEMA "telemetria" (MEDICIONES ANALÓGICAS)
-- ----------------------------------------------------------------------------

-- 4.1 Catálogo de variables de telemetría física
CREATE TABLE IF NOT EXISTS telemetria.variables_catalogo (
    id SERIAL PRIMARY KEY,
    codigo VARCHAR(50) NOT NULL UNIQUE,
    nombre VARCHAR(100) NOT NULL,
    descripcion TEXT,
    subsistema_componente VARCHAR(50) NOT NULL, -- 'BATERIA', 'SOLAR', 'CARGA', 'RED', 'TERMICO'
    unidad_medida VARCHAR(20) NOT NULL,
    escala_modbus VARCHAR(50) NOT NULL DEFAULT '1:1',
    rango_min_fisico NUMERIC(10,2),
    rango_max_fisico NUMERIC(10,2)
);

COMMENT ON TABLE telemetria.variables_catalogo IS 'Diccionario y catálogo de variables analógicas físicas registradas.';

-- 4.2 Tabla principal de lecturas de telemetría (Formato ancho optimizado)
CREATE TABLE IF NOT EXISTS telemetria.lecturas (
    id BIGSERIAL PRIMARY KEY,
    inversor_id INT NOT NULL,
    fecha_hora TIMESTAMPTZ NOT NULL,
    read_ts_unix NUMERIC(16,6) NOT NULL,
    
    -- Variables de Batería (DC)
    tension_bateria_v NUMERIC(6,2),
    corriente_bateria_a NUMERIC(7,2), -- Con signo (+: descarga, -: carga)
    potencia_bateria_w NUMERIC(9,2),  -- Calculada (+: entrega a la microrred, -: absorbe de solar/red)
    soc_bateria_pct INT,             -- State of Charge (0 - 100%)
    
    -- Variables Fotovoltaicas (PV)
    tension_pv_v NUMERIC(6,2),
    corriente_pv_a NUMERIC(6,2),
    potencia_pv_w NUMERIC(8,2),
    
    -- Variables de Consumo / Carga (AC Salida Inversor)
    tension_salida_v NUMERIC(6,2),
    corriente_salida_a NUMERIC(6,2),
    frecuencia_salida_hz NUMERIC(5,2),
    potencia_activa_salida_w NUMERIC(8,2),
    potencia_aparente_salida_va NUMERIC(8,2),
    porcentaje_carga_pct INT,
    
    -- Variables de Conexión a Red Eléctrica (AC Grid Import)
    tension_red_v NUMERIC(6,2),
    corriente_red_a NUMERIC(6,2),
    frecuencia_red_hz NUMERIC(5,2),
    potencia_red_w NUMERIC(8,2),
    
    -- Variables Térmicas
    temperatura_inversor_1_c NUMERIC(5,2),
    temperatura_inversor_2_c NUMERIC(5,2),
    temperatura_bateria_c NUMERIC(5,2),
    temperatura_ambiente_c NUMERIC(5,2),
    
    -- Metadatos de integridad y carga
    es_imputado BOOLEAN NOT NULL DEFAULT FALSE,
    fecha_insercion TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    -- Restricciones de Clave y Unicidad
    CONSTRAINT fk_lectura_inversor FOREIGN KEY (inversor_id)
        REFERENCES microrred.inversores (id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT uq_lectura_inversor_tiempo UNIQUE (inversor_id, fecha_hora),
    
    -- Restricciones CHECK de Validación Física de Datos
    CONSTRAINT chk_telemetria_soc CHECK (soc_bateria_pct IS NULL OR (soc_bateria_pct >= 0 AND soc_bateria_pct <= 100)),
    CONSTRAINT chk_telemetria_vbat CHECK (tension_bateria_v IS NULL OR (tension_bateria_v >= 0.0 AND tension_bateria_v <= 80.0)),
    CONSTRAINT chk_telemetria_vpv CHECK (tension_pv_v IS NULL OR (tension_pv_v >= 0.0 AND tension_pv_v <= 600.0)),
    CONSTRAINT chk_telemetria_ppv CHECK (potencia_pv_w IS NULL OR (potencia_pv_w >= 0.0 AND potencia_pv_w <= 20000.0)),
    CONSTRAINT chk_telemetria_frec_red CHECK (frecuencia_red_hz IS NULL OR (frecuencia_red_hz >= 0.0 AND frecuencia_red_hz <= 70.0)),
    CONSTRAINT chk_telemetria_frec_out CHECK (frecuencia_salida_hz IS NULL OR (frecuencia_salida_hz >= 0.0 AND frecuencia_salida_hz <= 70.0)),
    CONSTRAINT chk_telemetria_pct_carga CHECK (porcentaje_carga_pct IS NULL OR (porcentaje_carga_pct >= 0 AND porcentaje_carga_pct <= 300)),
    CONSTRAINT chk_telemetria_temperaturas CHECK (
        (temperatura_inversor_1_c IS NULL OR (temperatura_inversor_1_c >= -20.0 AND temperatura_inversor_1_c <= 150.0)) AND
        (temperatura_inversor_2_c IS NULL OR (temperatura_inversor_2_c >= -20.0 AND temperatura_inversor_2_c <= 150.0))
    )
);

COMMENT ON TABLE telemetria.lecturas IS 'Series de tiempo de lecturas físicas de los inversores (una fila por instante de telemetría).';

-- ----------------------------------------------------------------------------
-- 5. TABLAS DEL ESQUEMA "operacion" (CONTEXTO Y ALARMAS)
-- ----------------------------------------------------------------------------

-- 5.1 Registros de contexto de la microrred (Cómputo, Climatización, Operación)
CREATE TABLE IF NOT EXISTS operacion.registros_contexto (
    id BIGINT PRIMARY KEY,
    fecha_registro TIMESTAMPTZ NOT NULL,
    fecha_inicio TIMESTAMPTZ NOT NULL,
    fecha_fin TIMESTAMPTZ NOT NULL,
    inversor_id INT NOT NULL,
    origen VARCHAR(100) NOT NULL, -- e.g. 'workstation1_log', 'workstation2_log', 'manual_annotation'
    dispositivo VARCHAR(100),
    tipo_tarea VARCHAR(150),
    descripcion_textual TEXT NOT NULL,
    payload_json JSONB NOT NULL,
    datos_personales_anonimizados BOOLEAN NOT NULL DEFAULT FALSE,
    fecha_insercion TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_contexto_inversor FOREIGN KEY (inversor_id)
        REFERENCES microrred.inversores (id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT chk_contexto_intervalo CHECK (fecha_fin >= fecha_inicio)
);

COMMENT ON TABLE operacion.registros_contexto IS 'Bitácora y contexto operacional con soporte JSONB de anotaciones y cargas de cómputo.';

-- 5.2 Catálogo de tipos de alarma del sistema
CREATE TABLE IF NOT EXISTS operacion.catalogo_tipos_alarma (
    id SERIAL PRIMARY KEY,
    codigo VARCHAR(30) NOT NULL UNIQUE,
    nombre VARCHAR(100) NOT NULL,
    severidad_defecto operacion.nivel_severidad NOT NULL DEFAULT 'WARNING',
    parametro_evaluado VARCHAR(50) NOT NULL,
    unidad_medida VARCHAR(20) NOT NULL,
    descripcion TEXT NOT NULL,
    accion_recomendada TEXT
);

COMMENT ON TABLE operacion.catalogo_tipos_alarma IS 'Definición normalizada de tipos de incidentes, severidad base y recomendaciones.';

-- 5.3 Umbrales de configuración operativa por inversor
CREATE TABLE IF NOT EXISTS operacion.umbrales_configuracion (
    id SERIAL PRIMARY KEY,
    inversor_id INT NOT NULL,
    tipo_alarma_id INT NOT NULL,
    umbral_warning NUMERIC(10,2) NOT NULL,
    umbral_critical NUMERIC(10,2) NOT NULL,
    activo BOOLEAN NOT NULL DEFAULT TRUE,
    fecha_modificacion TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    modificado_por VARCHAR(100) NOT NULL DEFAULT CURRENT_USER,
    CONSTRAINT fk_umbral_inversor FOREIGN KEY (inversor_id)
        REFERENCES microrred.inversores (id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_umbral_tipo FOREIGN KEY (tipo_alarma_id)
        REFERENCES operacion.catalogo_tipos_alarma (id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT uq_umbral_inversor_tipo UNIQUE (inversor_id, tipo_alarma_id)
);

COMMENT ON TABLE operacion.umbrales_configuracion IS 'Umbrales parametrizables para disparo de alarmas en cada inversor.';

-- 5.4 Tabla de alarmas e incidentes operacionales (Línea de profundización 5)
CREATE TABLE IF NOT EXISTS operacion.alarmas (
    id BIGSERIAL PRIMARY KEY,
    inversor_id INT NOT NULL,
    tipo_alarma_id INT NOT NULL,
    fecha_deteccion TIMESTAMPTZ NOT NULL,
    lectura_id BIGINT,
    severidad operacion.nivel_severidad NOT NULL,
    parametro VARCHAR(50) NOT NULL,
    valor_detectado NUMERIC(10,2) NOT NULL,
    umbral_disparado NUMERIC(10,2) NOT NULL,
    mensaje_alarma TEXT NOT NULL,
    estado operacion.estado_alarma NOT NULL DEFAULT 'ACTIVA',
    fecha_resolucion TIMESTAMPTZ,
    usuario_resolutor VARCHAR(100),
    comentario_resolucion TEXT,
    fecha_creacion TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_alarma_inversor FOREIGN KEY (inversor_id)
        REFERENCES microrred.inversores (id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_alarma_tipo FOREIGN KEY (tipo_alarma_id)
        REFERENCES operacion.catalogo_tipos_alarma (id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_alarma_lectura FOREIGN KEY (lectura_id)
        REFERENCES telemetria.lecturas (id)
        ON DELETE SET NULL ON UPDATE CASCADE,
    CONSTRAINT chk_resolucion_consistente CHECK (
        (estado IN ('RESUELTA', 'DESCARTADA') AND fecha_resolucion IS NOT NULL AND usuario_resolutor IS NOT NULL) OR
        (estado IN ('ACTIVA', 'EN_REVISION') AND fecha_resolucion IS NULL)
    )
);

COMMENT ON TABLE operacion.alarmas IS 'Registro operacional de alarmas disparadas automáticamente por triggers PL/pgSQL.';

-- 5.5 Consolidado y resumen diario de incidentes
CREATE TABLE IF NOT EXISTS operacion.resumen_diario_alarmas (
    id SERIAL PRIMARY KEY,
    fecha DATE NOT NULL,
    inversor_id INT NOT NULL,
    total_alarmas INT NOT NULL DEFAULT 0,
    total_criticas INT NOT NULL DEFAULT 0,
    total_advertencias INT NOT NULL DEFAULT 0,
    total_informativas INT NOT NULL DEFAULT 0,
    tiempo_promedio_resolucion_min NUMERIC(8,2),
    fecha_generacion TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_resumen_inversor FOREIGN KEY (inversor_id)
        REFERENCES microrred.inversores (id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT uq_resumen_fecha_inversor UNIQUE (fecha, inversor_id)
);

COMMENT ON TABLE operacion.resumen_diario_alarmas IS 'Indicadores consolidados diarios de eventos para la gestión de mantenimiento.';

-- ----------------------------------------------------------------------------
-- 6. TABLAS DEL ESQUEMA "auditoria" (CHANGE DATA CAPTURE / LEY 1581)
-- ----------------------------------------------------------------------------

-- 6.1 Bitácora inmutable de auditoría general
CREATE TABLE IF NOT EXISTS auditoria.registro_cambios (
    id BIGSERIAL PRIMARY KEY,
    fecha_hora TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    usuario_bd VARCHAR(100) NOT NULL DEFAULT CURRENT_USER,
    rol_bd VARCHAR(100) NOT NULL DEFAULT SESSION_USER,
    accion auditoria.accion_auditoria NOT NULL,
    esquema_nombre VARCHAR(50) NOT NULL,
    tabla_nombre VARCHAR(50) NOT NULL,
    registro_id VARCHAR(100),
    datos_anteriores JSONB,
    datos_nuevos JSONB,
    diferencias JSONB,
    ip_cliente INET,
    aplicacion_cliente VARCHAR(150)
);

COMMENT ON TABLE auditoria.registro_cambios IS 'Bitácora inmutable de auditoría forense y cambios en tablas críticas.';
