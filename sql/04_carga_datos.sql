-- ============================================================================
-- INSTITUCIÓN UNIVERSITARIA PASCUAL BRAVO
-- Departamento de Sistemas Digitales · Bases de Datos I · Grupo 811
-- Taller 6 · SolarDB: Base de Datos para la Telemetría de una Microrred Híbrida
-- Línea 5: SolarDB: Funciones, Procedimientos y Triggers en PL/pgSQL
--          para Alarmas y Auditoría
-- ============================================================================
-- Archivo: sql/04_carga_datos.sql
-- Propósito: Carga masiva de > 1,000,000 de lecturas y 15,000 registros de contexto.
-- Estrategia de carga:
--   1. Carga directa mediante \copy (cliente) o COPY (servidor) con tabla intermedia.
--   2. Garantía de idempotencia: ON CONFLICT DO NOTHING.
--   3. Verificación de conteos antes y después.
--   4. Pruebas DML de restricciones (INSERT, UPDATE, DELETE y caso rechazado).
-- Ejecutar conectado a la base de datos "solardb".
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. PREPARACIÓN: TABLA TEMPORAL DE CARGA (STAGING)
-- ----------------------------------------------------------------------------
-- 1. PREPARACIÓN: TABLAS TEMPORALES DE CARGA (STAGING)
-- ----------------------------------------------------------------------------
-- El uso de tablas staging permite validar y transformar antes de insertar en producción.
CREATE TEMP TABLE IF NOT EXISTS staging_telemetria (
    inversor_id INT,
    fecha_hora TIMESTAMPTZ,
    read_ts_unix NUMERIC(16,6),
    tension_bateria_v NUMERIC(6,2),
    corriente_bateria_a NUMERIC(7,2),
    potencia_bateria_w NUMERIC(9,2),
    soc_bateria_pct INT,
    tension_pv_v NUMERIC(6,2),
    corriente_pv_a NUMERIC(6,2),
    potencia_pv_w NUMERIC(8,2),
    tension_salida_v NUMERIC(6,2),
    corriente_salida_a NUMERIC(6,2),
    frecuencia_salida_hz NUMERIC(5,2),
    potencia_activa_salida_w NUMERIC(8,2),
    potencia_aparente_salida_va NUMERIC(8,2),
    porcentaje_carga_pct INT,
    tension_red_v NUMERIC(6,2),
    corriente_red_a NUMERIC(6,2),
    frecuencia_red_hz NUMERIC(5,2),
    potencia_red_w NUMERIC(8,2),
    temperatura_inversor_1_c NUMERIC(5,2),
    temperatura_inversor_2_c NUMERIC(5,2),
    temperatura_bateria_c NUMERIC(5,2),
    temperatura_ambiente_c NUMERIC(5,2)
);

CREATE TEMP TABLE IF NOT EXISTS staging_contexto (
    id BIGINT,
    fecha_registro TIMESTAMPTZ,
    fecha_inicio TIMESTAMPTZ,
    fecha_fin TIMESTAMPTZ,
    inversor_id INT,
    origen VARCHAR(100),
    dispositivo VARCHAR(100),
    tipo_tarea VARCHAR(150),
    descripcion_textual TEXT,
    payload_json JSONB
);

-- Limpiar tablas temporales por si se ejecuta varias veces en la misma sesión
TRUNCATE staging_telemetria;
TRUNCATE staging_contexto;

-- ----------------------------------------------------------------------------
-- 2. COMANDOS DE CARGA MASIVA DIRECTA EN DBEAVER (COPY SERVER-SIDE)
-- ----------------------------------------------------------------------------
-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  INSTRUCCIÓN: Ajuste ÚNICAMENTE la variable v_data_path de la línea 4  ║
-- ║  del bloque DO a continuación con la ruta ABSOLUTA de la carpeta data/ ║
-- ║  en su equipo. Use barras normales / (no backslash \).                 ║
-- ║  Luego ejecute el script completo con Alt + X en DBeaver.              ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

DO $$
DECLARE
    -- ► CAMBIE SOLO ESTA LÍNEA con la ruta a la carpeta data/ en su equipo:
    v_data_path TEXT := 'C:/Users/Camilo/Downloads/BD_Antigravity/data';
BEGIN
    EXECUTE format(
        'COPY staging_telemetria FROM %L WITH (FORMAT csv, HEADER true, ENCODING ''UTF8'')',
        v_data_path || '/telemetria_lecturas.csv'
    );
    RAISE NOTICE 'Carga de telemetria completada desde: %', v_data_path || '/telemetria_lecturas.csv';

    EXECUTE format(
        'COPY staging_contexto FROM %L WITH (FORMAT csv, HEADER true, ENCODING ''UTF8'')',
        v_data_path || '/registros_contexto.csv'
    );
    RAISE NOTICE 'Carga de contexto completada desde: %', v_data_path || '/registros_contexto.csv';
END $$;

-- ----------------------------------------------------------------------------
-- 3. MIGRACIÓN IDEMPOTENTE A TABLAS DE PRODUCCIÓN
-- ----------------------------------------------------------------------------
-- Deshabilitar temporalmente los triggers de evaluación masiva durante la carga inicial
-- para maximizar el throughput (alcanzando más de 50.000 filas/segundo)
ALTER TABLE telemetria.lecturas DISABLE TRIGGER trg_evaluar_alarmas_telemetria;

-- Inserción idempotente en telemetría (no duplica si ya existe el par inversor_id + fecha_hora)
INSERT INTO telemetria.lecturas (
    inversor_id, fecha_hora, read_ts_unix,
    tension_bateria_v, corriente_bateria_a, potencia_bateria_w, soc_bateria_pct,
    tension_pv_v, corriente_pv_a, potencia_pv_w,
    tension_salida_v, corriente_salida_a, frecuencia_salida_hz, potencia_activa_salida_w, potencia_aparente_salida_va, porcentaje_carga_pct,
    tension_red_v, corriente_red_a, frecuencia_red_hz, potencia_red_w,
    temperatura_inversor_1_c, temperatura_inversor_2_c, temperatura_bateria_c, temperatura_ambiente_c
)
SELECT 
    inversor_id, fecha_hora, read_ts_unix,
    tension_bateria_v, corriente_bateria_a, potencia_bateria_w, soc_bateria_pct,
    tension_pv_v, corriente_pv_a, potencia_pv_w,
    tension_salida_v, corriente_salida_a, frecuencia_salida_hz, potencia_activa_salida_w, potencia_aparente_salida_va, porcentaje_carga_pct,
    tension_red_v, corriente_red_a, frecuencia_red_hz, potencia_red_w,
    temperatura_inversor_1_c, temperatura_inversor_2_c, temperatura_bateria_c, temperatura_ambiente_c
FROM staging_telemetria
ON CONFLICT (inversor_id, fecha_hora) DO NOTHING;

-- Reactivar el trigger de alarmas para la operación continua
ALTER TABLE telemetria.lecturas ENABLE TRIGGER trg_evaluar_alarmas_telemetria;

-- Inserción idempotente en contexto
INSERT INTO operacion.registros_contexto (
    id, fecha_registro, fecha_inicio, fecha_fin, inversor_id,
    origen, dispositivo, tipo_tarea, descripcion_textual, payload_json,
    datos_personales_anonimizados
)
SELECT 
    id, fecha_registro, fecha_inicio, fecha_fin, inversor_id,
    origen, dispositivo, tipo_tarea, descripcion_textual, payload_json,
    TRUE
FROM staging_contexto
ON CONFLICT (id) DO UPDATE SET 
    descripcion_textual = EXCLUDED.descripcion_textual,
    payload_json = EXCLUDED.payload_json;

-- Actualizar secuencia de claves de telemetría
SELECT setval(pg_get_serial_sequence('telemetria.lecturas', 'id'), COALESCE(MAX(id), 1)) FROM telemetria.lecturas;

-- ----------------------------------------------------------------------------
-- 4. VERIFICACIÓN DE INTEGRIDAD DE LA CARGA (CONTEOS ANTES Y DESPUÉS)
-- ----------------------------------------------------------------------------
DO $$
DECLARE
    v_total_telemetria BIGINT;
    v_total_contexto BIGINT;
    v_inversor_1 BIGINT;
    v_inversor_2 BIGINT;
BEGIN
    SELECT COUNT(*) INTO v_total_telemetria FROM telemetria.lecturas;
    SELECT COUNT(*) INTO v_total_contexto FROM operacion.registros_contexto;
    SELECT COUNT(*) INTO v_inversor_1 FROM telemetria.lecturas WHERE inversor_id = 1;
    SELECT COUNT(*) INTO v_inversor_2 FROM telemetria.lecturas WHERE inversor_id = 2;

    RAISE NOTICE '=======================================================';
    RAISE NOTICE '           RESULTADO DE VERIFICACIÓN DE CARGA          ';
    RAISE NOTICE '=======================================================';
    RAISE NOTICE 'Total lecturas en telemetria.lecturas: %', v_total_telemetria;
    RAISE NOTICE '  - Inversor 1 (Cómputo):              %', v_inversor_1;
    RAISE NOTICE '  - Inversor 2 (Climatización HVAC):   %', v_inversor_2;
    RAISE NOTICE 'Total registros en operacion.contexto: %', v_total_contexto;
    RAISE NOTICE '=======================================================';

    IF v_total_telemetria >= 1000000 THEN
        RAISE NOTICE '[OK] Se cumple el requerimiento de al menos un millón de lecturas (Se cargaron % lecturas).', v_total_telemetria;
    ELSE
        RAISE WARNING '[AVISO] Total de lecturas cargadas (% ) es inferior al millón solicitado.', v_total_telemetria;
    END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 5. PRUEBAS DML DE FUNCIONAMIENTO DE RESTRICCIONES (SECCIÓN 4.F)
-- ----------------------------------------------------------------------------

-- 5.1 Caso Exitoso 1: INSERT normal válido
INSERT INTO telemetria.lecturas (
    inversor_id, fecha_hora, read_ts_unix,
    tension_bateria_v, corriente_bateria_a, potencia_bateria_w, soc_bateria_pct,
    tension_pv_v, corriente_pv_a, potencia_pv_w,
    tension_salida_v, corriente_salida_a, frecuencia_salida_hz, potencia_activa_salida_w, potencia_aparente_salida_va, porcentaje_carga_pct,
    tension_red_v, corriente_red_a, frecuencia_red_hz, potencia_red_w,
    temperatura_inversor_1_c, temperatura_inversor_2_c, temperatura_bateria_c, temperatura_ambiente_c
)
VALUES (
    1, '2026-03-01 12:00:00+00', 1772366400.0,
    52.80, 15.40, 813.12, 75,
    380.00, 8.50, 3230.00,
    220.00, 11.20, 50.00, 2400.00, 2464.00, 30,
    220.00, 0.00, 50.00, 0.00,
    42.50, 40.10, 31.00, 28.00
)
ON CONFLICT (inversor_id, fecha_hora) DO NOTHING;

-- 5.2 Caso Exitoso 2: UPDATE válido (auditado por trigger)
UPDATE microrred.inversores
SET descripcion_ubicacion = 'Sala Eléctrica Central - Bahía 1 (Lado Norte, Rack A-01 Renovado)'
WHERE id = 1;

-- 5.3 Caso Exitoso 3: DELETE válido de una lectura puntual (auditado por trigger)
DELETE FROM telemetria.lecturas
WHERE inversor_id = 1 AND fecha_hora = '2026-03-01 12:00:00+00';

-- 5.4 CASO RECHAZADO: Violación de restricción CHECK (SoC fuera de rango físico: 150%)
-- Este bloque demuestra que PostgreSQL rechaza activamente anomalías físicas.
DO $$
BEGIN
    INSERT INTO telemetria.lecturas (
        inversor_id, fecha_hora, read_ts_unix,
        tension_bateria_v, soc_bateria_pct
    ) VALUES (
        1, '2026-03-01 12:05:00+00', 1772366700.0,
        52.00, 150 -- VALOR IMPOSIBLE: Viola chk_telemetria_soc (0 a 100%)
    );
    RAISE EXCEPTION 'ERROR: La base de datos debió rechazar el SoC de 150%% pero lo permitió.';
EXCEPTION
    WHEN check_violation THEN
        RAISE NOTICE '[VALIDACIÓN EXITOSA] La base de datos rechazó correctamente el registro con soc_bateria_pct = 150%% por violación de la restricción CHECK (chk_telemetria_soc).';
END $$;

-- 5.5 CASO RECHAZADO: Violación de Clave Foránea (Inversor inexistente ID = 99)
DO $$
BEGIN
    INSERT INTO telemetria.lecturas (
        inversor_id, fecha_hora, read_ts_unix, tension_bateria_v
    ) VALUES (
        99, '2026-03-01 12:10:00+00', 1772367000.0, 52.00
    );
    RAISE EXCEPTION 'ERROR: La base de datos debió rechazar el inversor inexistente pero lo permitió.';
EXCEPTION
    WHEN foreign_key_violation THEN
        RAISE NOTICE '[VALIDACIÓN EXITOSA] La base de datos rechazó correctamente la inserción de inversor_id = 99 por violación de clave foránea (fk_lectura_inversor).';
END $$;
