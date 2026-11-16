-- ============================================================================
-- INSTITUCIÓN UNIVERSITARIA PASCUAL BRAVO
-- Departamento de Sistemas Digitales · Bases de Datos I · Grupo 811
-- Taller 6 · SolarDB: Base de Datos para la Telemetría de una Microrred Híbrida
-- Línea 5: SolarDB: Funciones, Procedimientos y Triggers en PL/pgSQL
--          para Alarmas y Auditoría
-- ============================================================================
-- Archivo: sql/03_linea5_triggers_funciones_procedimientos.sql
-- Propósito: Implementación completa de la lógica procedural en PL/pgSQL:
--   1. Funciones de evaluación de alarmas, auditoría CDC, cálculo energético y Habeas Data.
--   2. Triggers de disparo de alarmas, auditoría forense y saneamiento de datos.
--   3. Procedimientos almacenados para el ciclo de vida de alarmas y consolidación.
-- Ejecutar conectado a la base de datos "solardb" después de 02_catalogos_dml.sql.
-- ============================================================================

-- ============================================================================
-- SECCIÓN A: FUNCIONES EN PL/pgSQL
-- ============================================================================

-- ----------------------------------------------------------------------------
-- A.1 Función Trigger: Detección y Disparo Automático de Alarmas
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION operacion.fn_evaluar_alertas_telemetria()
RETURNS TRIGGER 
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_umbral RECORD;
    v_existe_activa BOOLEAN;
    v_mensaje TEXT;
    v_severidad operacion.nivel_severidad;
BEGIN
    -- 1. EVALUACIÓN DE ESTADO DE CARGA DE BATERÍA (SoC)
    IF NEW.soc_bateria_pct IS NOT NULL THEN
        -- Obtener umbrales de SoC para el inversor
        SELECT u.umbral_warning, u.umbral_critical, t.id AS tipo_id
        INTO v_umbral
        FROM operacion.umbrales_configuracion u
        JOIN operacion.catalogo_tipos_alarma t ON t.id = u.tipo_alarma_id
        WHERE u.inversor_id = NEW.inversor_id AND t.codigo = 'ALM-BAT-LOW-WARN' AND u.activo = TRUE;

        IF FOUND AND NEW.soc_bateria_pct <= v_umbral.umbral_critical THEN
            -- Alarma Crítica de Descarga Profunda (SoC <= 10%)
            SELECT EXISTS (
                SELECT 1 FROM operacion.alarmas 
                WHERE inversor_id = NEW.inversor_id 
                  AND tipo_alarma_id = 2 -- ALM-BAT-LOW-CRIT
                  AND estado = 'ACTIVA'
                  AND fecha_deteccion >= (NEW.fecha_hora - INTERVAL '15 minutes')
            ) INTO v_existe_activa;

            IF NOT v_existe_activa THEN
                INSERT INTO operacion.alarmas (
                    inversor_id, tipo_alarma_id, fecha_deteccion, lectura_id, severidad,
                    parametro, valor_detectado, umbral_disparado, mensaje_alarma
                ) VALUES (
                    NEW.inversor_id, 2, NEW.fecha_hora, NEW.id, 'CRITICAL',
                    'soc_bateria_pct', NEW.soc_bateria_pct, v_umbral.umbral_critical,
                    format('¡Descarga crítica de batería! SoC alcanzó %s%% (Umbral crítico: %s%%). Riesgo de desconexión forzada.',
                           NEW.soc_bateria_pct, v_umbral.umbral_critical)
                );
            END IF;
        ELSIF FOUND AND NEW.soc_bateria_pct <= v_umbral.umbral_warning THEN
            -- Alarma de Advertencia de Batería Baja (SoC <= 20%)
            SELECT EXISTS (
                SELECT 1 FROM operacion.alarmas 
                WHERE inversor_id = NEW.inversor_id 
                  AND tipo_alarma_id = 1 -- ALM-BAT-LOW-WARN
                  AND estado = 'ACTIVA'
                  AND fecha_deteccion >= (NEW.fecha_hora - INTERVAL '30 minutes')
            ) INTO v_existe_activa;

            IF NOT v_existe_activa THEN
                INSERT INTO operacion.alarmas (
                    inversor_id, tipo_alarma_id, fecha_deteccion, lectura_id, severidad,
                    parametro, valor_detectado, umbral_disparado, mensaje_alarma
                ) VALUES (
                    NEW.inversor_id, 1, NEW.fecha_hora, NEW.id, 'WARNING',
                    'soc_bateria_pct', NEW.soc_bateria_pct, v_umbral.umbral_warning,
                    format('Advertencia: SoC de batería descendió a %s%% (Umbral de advertencia: %s%%).',
                           NEW.soc_bateria_pct, v_umbral.umbral_warning)
                );
            END IF;
        END IF;
    END IF;

    -- 2. EVALUACIÓN DE TENSIÓN DE BATERÍA (Subtensión y Sobretensión)
    IF NEW.tension_bateria_v IS NOT NULL THEN
        -- Subtensión de Batería (< 44.0 V)
        SELECT u.umbral_critical INTO v_umbral
        FROM operacion.umbrales_configuracion u
        JOIN operacion.catalogo_tipos_alarma t ON t.id = u.tipo_alarma_id
        WHERE u.inversor_id = NEW.inversor_id AND t.codigo = 'ALM-BAT-UVOLT-CRIT' AND u.activo = TRUE;

        IF FOUND AND NEW.tension_bateria_v <= v_umbral.umbral_critical THEN
            SELECT EXISTS (
                SELECT 1 FROM operacion.alarmas 
                WHERE inversor_id = NEW.inversor_id AND tipo_alarma_id = 3 AND estado = 'ACTIVA'
                  AND fecha_deteccion >= (NEW.fecha_hora - INTERVAL '15 minutes')
            ) INTO v_existe_activa;

            IF NOT v_existe_activa THEN
                INSERT INTO operacion.alarmas (
                    inversor_id, tipo_alarma_id, fecha_deteccion, lectura_id, severidad,
                    parametro, valor_detectado, umbral_disparado, mensaje_alarma
                ) VALUES (
                    NEW.inversor_id, 3, NEW.fecha_hora, NEW.id, 'CRITICAL',
                    'tension_bateria_v', NEW.tension_bateria_v, v_umbral.umbral_critical,
                    format('Subtensión severa de batería: %s V (Umbral crítico: %s V). Inversor en riesgo de bloqueo.',
                           NEW.tension_bateria_v, v_umbral.umbral_critical)
                );
            END IF;
        END IF;

        -- Sobretensión de Batería (> 58.4 V)
        SELECT u.umbral_critical INTO v_umbral
        FROM operacion.umbrales_configuracion u
        JOIN operacion.catalogo_tipos_alarma t ON t.id = u.tipo_alarma_id
        WHERE u.inversor_id = NEW.inversor_id AND t.codigo = 'ALM-BAT-OVOLT-CRIT' AND u.activo = TRUE;

        IF FOUND AND NEW.tension_bateria_v >= v_umbral.umbral_critical THEN
            SELECT EXISTS (
                SELECT 1 FROM operacion.alarmas 
                WHERE inversor_id = NEW.inversor_id AND tipo_alarma_id = 4 AND estado = 'ACTIVA'
                  AND fecha_deteccion >= (NEW.fecha_hora - INTERVAL '15 minutes')
            ) INTO v_existe_activa;

            IF NOT v_existe_activa THEN
                INSERT INTO operacion.alarmas (
                    inversor_id, tipo_alarma_id, fecha_deteccion, lectura_id, severidad,
                    parametro, valor_detectado, umbral_disparado, mensaje_alarma
                ) VALUES (
                    NEW.inversor_id, 4, NEW.fecha_hora, NEW.id, 'CRITICAL',
                    'tension_bateria_v', NEW.tension_bateria_v, v_umbral.umbral_critical,
                    format('Sobretensión crítica en banco de batería: %s V (Umbral de absorción máximo: %s V).',
                           NEW.tension_bateria_v, v_umbral.umbral_critical)
                );
            END IF;
        END IF;
    END IF;

    -- 3. EVALUACIÓN TÉRMICA DEL INVERSOR (temper1)
    IF NEW.temperatura_inversor_1_c IS NOT NULL THEN
        SELECT u.umbral_warning, u.umbral_critical INTO v_umbral
        FROM operacion.umbrales_configuracion u
        JOIN operacion.catalogo_tipos_alarma t ON t.id = u.tipo_alarma_id
        WHERE u.inversor_id = NEW.inversor_id AND t.codigo = 'ALM-INV-TEMP-WARN' AND u.activo = TRUE;

        IF FOUND AND NEW.temperatura_inversor_1_c >= v_umbral.umbral_critical THEN
            SELECT EXISTS (
                SELECT 1 FROM operacion.alarmas 
                WHERE inversor_id = NEW.inversor_id AND tipo_alarma_id = 7 AND estado = 'ACTIVA'
                  AND fecha_deteccion >= (NEW.fecha_hora - INTERVAL '15 minutes')
            ) INTO v_existe_activa;

            IF NOT v_existe_activa THEN
                INSERT INTO operacion.alarmas (
                    inversor_id, tipo_alarma_id, fecha_deteccion, lectura_id, severidad,
                    parametro, valor_detectado, umbral_disparado, mensaje_alarma
                ) VALUES (
                    NEW.inversor_id, 7, NEW.fecha_hora, NEW.id, 'CRITICAL',
                    'temperatura_inversor_1_c', NEW.temperatura_inversor_1_c, v_umbral.umbral_critical,
                    format('Sobrecalentamiento crítico de disipador/IGBTs: %s °C (Umbral crítico: %s °C).',
                           NEW.temperatura_inversor_1_c, v_umbral.umbral_critical)
                );
            END IF;
        ELSIF FOUND AND NEW.temperatura_inversor_1_c >= v_umbral.umbral_warning THEN
            SELECT EXISTS (
                SELECT 1 FROM operacion.alarmas 
                WHERE inversor_id = NEW.inversor_id AND tipo_alarma_id = 6 AND estado = 'ACTIVA'
                  AND fecha_deteccion >= (NEW.fecha_hora - INTERVAL '30 minutes')
            ) INTO v_existe_activa;

            IF NOT v_existe_activa THEN
                INSERT INTO operacion.alarmas (
                    inversor_id, tipo_alarma_id, fecha_deteccion, lectura_id, severidad,
                    parametro, valor_detectado, umbral_disparado, mensaje_alarma
                ) VALUES (
                    NEW.inversor_id, 6, NEW.fecha_hora, NEW.id, 'WARNING',
                    'temperatura_inversor_1_c', NEW.temperatura_inversor_1_c, v_umbral.umbral_warning,
                    format('Temperatura elevada en inversor: %s °C (Umbral: %s °C).',
                           NEW.temperatura_inversor_1_c, v_umbral.umbral_warning)
                );
            END IF;
        END IF;
    END IF;

    -- 4. EVALUACIÓN DE SOBRECARGA EN SALIDA AC
    IF NEW.porcentaje_carga_pct IS NOT NULL AND NEW.porcentaje_carga_pct >= 95 THEN
        SELECT EXISTS (
            SELECT 1 FROM operacion.alarmas 
            WHERE inversor_id = NEW.inversor_id AND tipo_alarma_id = 9 AND estado = 'ACTIVA'
              AND fecha_deteccion >= (NEW.fecha_hora - INTERVAL '15 minutes')
        ) INTO v_existe_activa;

        IF NOT v_existe_activa THEN
            INSERT INTO operacion.alarmas (
                inversor_id, tipo_alarma_id, fecha_deteccion, lectura_id, severidad,
                parametro, valor_detectado, umbral_disparado, mensaje_alarma
            ) VALUES (
                NEW.inversor_id, 9, NEW.fecha_hora, NEW.id, 'WARNING',
                'porcentaje_carga_pct', NEW.porcentaje_carga_pct, 95.00,
                format('Sobrecarga de salida detectada: %s%% de la capacidad nominal.', NEW.porcentaje_carga_pct)
            );
        END IF;
    END IF;

    -- 5. EVALUACIÓN DE PÉRDIDA DE RED PÚBLICA (MODO ISLA)
    IF NEW.tension_red_v IS NOT NULL AND NEW.tension_red_v < 50.00 THEN
        SELECT EXISTS (
            SELECT 1 FROM operacion.alarmas 
            WHERE inversor_id = NEW.inversor_id AND tipo_alarma_id = 10 AND estado = 'ACTIVA'
              AND fecha_deteccion >= (NEW.fecha_hora - INTERVAL '1 hour')
        ) INTO v_existe_activa;

        IF NOT v_existe_activa THEN
            INSERT INTO operacion.alarmas (
                inversor_id, tipo_alarma_id, fecha_deteccion, lectura_id, severidad,
                parametro, valor_detectado, umbral_disparado, mensaje_alarma
            ) VALUES (
                NEW.inversor_id, 10, NEW.fecha_hora, NEW.id, 'INFO',
                'tension_red_v', NEW.tension_red_v, 50.00,
                format('Pérdida de suministro de red pública (%s V). El subsistema opera en modo isla autónomo.', NEW.tension_red_v)
            );
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION operacion.fn_evaluar_alertas_telemetria() IS 
'Trigger function para evaluación en tiempo real de variables físicas y disparo automático de incidentes con supresión de tormentas de alarmas.';

-- ----------------------------------------------------------------------------
-- A.2 Función Trigger: Auditoría Forense General (Change Data Capture)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION auditoria.fn_auditar_modificaciones()
RETURNS TRIGGER 
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_old_data JSONB := NULL;
    v_new_data JSONB := NULL;
    v_diff JSONB := NULL;
    v_registro_id TEXT := NULL;
BEGIN
    -- Capturar datos anteriores y nuevos según la operación
    IF TG_OP = 'INSERT' THEN
        v_new_data := to_jsonb(NEW);
        IF NEW ? 'id' THEN
            v_registro_id := (v_new_data->>'id');
        END IF;
    ELSIF TG_OP = 'UPDATE' THEN
        v_old_data := to_jsonb(OLD);
        v_new_data := to_jsonb(NEW);
        IF v_new_data ? 'id' THEN
            v_registro_id := (v_new_data->>'id');
        END IF;
        -- Calcular diferencias
        SELECT jsonb_object_agg(n.key, jsonb_build_object('antes', o.value, 'despues', n.value))
        INTO v_diff
        FROM jsonb_each(v_new_data) n
        JOIN jsonb_each(v_old_data) o ON n.key = o.key
        WHERE n.value IS DISTINCT FROM o.value;
    ELSIF TG_OP = 'DELETE' THEN
        v_old_data := to_jsonb(OLD);
        IF v_old_data ? 'id' THEN
            v_registro_id := (v_old_data->>'id');
        END IF;
    END IF;

    -- Registrar en bitácora inmutable
    INSERT INTO auditoria.registro_cambios (
        usuario_bd, rol_bd, accion, esquema_nombre, tabla_nombre,
        registro_id, datos_anteriores, datos_nuevos, diferencias,
        ip_cliente, aplicacion_cliente
    ) VALUES (
        CURRENT_USER,
        SESSION_USER,
        TG_OP::auditoria.accion_auditoria,
        TG_TABLE_SCHEMA,
        TG_TABLE_NAME,
        v_registro_id,
        v_old_data,
        v_new_data,
        v_diff,
        inet_client_addr(),
        current_setting('application_name', true)
    );

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;
END;
$$;

COMMENT ON FUNCTION auditoria.fn_auditar_modificaciones() IS 
'Función genérica de auditoría Change Data Capture (CDC) que almacena tuplas completas y diferencias en JSONB.';

-- ----------------------------------------------------------------------------
-- A.3 Función Trigger: Protección de Datos Personales (Ley 1581 de 2012)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION operacion.fn_sanitizar_contexto_habeas_data()
RETURNS TRIGGER 
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_payload JSONB;
    v_desc TEXT;
    v_cmd TEXT;
    v_dir TEXT;
BEGIN
    v_payload := NEW.payload_json;
    v_desc := NEW.descripcion_textual;

    -- 1. Anonimizar rutas de usuario del sistema de archivos (ej. /home/camilo/... -> .../proyecto/...)
    IF v_payload ? 'directory' THEN
        v_dir := v_payload->>'directory';
        -- Reemplazar rutas personales absolutas por rutas relativas genéricas
        v_dir := regexp_replace(v_dir, '^(/Users/[^/]+|/home/[^/]+|[A-Za-z]:\\[Uu]sers\\[^\\]+)', '[RUTA_PERSONAL_OFUSCADA]');
        v_payload := jsonb_set(v_payload, '{directory}', to_jsonb(v_dir));
    END IF;

    -- 2. Sanitizar comandos de consola que puedan exponer nombres de archivos sensibles o credenciales
    IF v_payload ? 'command' THEN
        v_cmd := v_payload->>'command';
        -- Ocultar posibles tokens, passwords o flags sensibles
        v_cmd := regexp_replace(v_cmd, '(--password|--token|--key)\s+[^\s]+', '\1 [OCULTO_LEY1581]', 'gi');
        v_payload := jsonb_set(v_payload, '{command}', to_jsonb(v_cmd));
    END IF;

    -- 3. Sanitizar descripción textual de datos identificativos personales (correos y nombres de cuenta)
    v_desc := regexp_replace(v_desc, '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}', '[CORREO_ANONIMIZADO]', 'g');

    -- Actualizar campos del registro
    NEW.descripcion_textual := v_desc;
    NEW.payload_json := v_payload;
    NEW.datos_personales_anonimizados := TRUE;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION operacion.fn_sanitizar_contexto_habeas_data() IS 
'Garantiza el cumplimiento de la Ley 1581 de 2012 ofuscando rutas locales, comandos de consola y correos en anotaciones de contexto.';

-- ----------------------------------------------------------------------------
-- A.4 Función de Negocio: Cálculo Numérico de Energía por Integración (kWh)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION telemetria.fn_calcular_energia_kwh(
    p_inversor_id INT,
    p_fecha_inicio TIMESTAMPTZ,
    p_fecha_fin TIMESTAMPTZ
)
RETURNS TABLE (
    inversor_id INT,
    energia_solar_generada_kwh NUMERIC(12,3),
    energia_entregada_carga_kwh NUMERIC(12,3),
    energia_importada_red_kwh NUMERIC(12,3),
    energia_neta_bateria_kwh NUMERIC(12,3),
    total_lecturas_integradas BIGINT,
    factor_cobertura_temporal_pct NUMERIC(5,2)
)
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    RETURN QUERY
    WITH lecturas_con_delta AS (
        SELECT 
            l.inversor_id,
            l.fecha_hora,
            l.potencia_pv_w,
            l.potencia_activa_salida_w,
            l.potencia_red_w,
            l.potencia_bateria_w,
            EXTRACT(EPOCH FROM (l.fecha_hora - LAG(l.fecha_hora) OVER (ORDER BY l.fecha_hora))) AS delta_segundos
        FROM telemetria.lecturas l
        WHERE l.inversor_id = p_inversor_id
          AND l.fecha_hora >= p_fecha_inicio
          AND l.fecha_hora < p_fecha_fin
    ),
    integracion AS (
        SELECT 
            d.inversor_id,
            -- Integración de potencia (W * s / 3,600,000 = kWh)
            -- Se limita delta_segundos a un máximo de 60 s para no extrapolar durante cortes prolongados
            SUM(COALESCE(d.potencia_pv_w, 0) * LEAST(d.delta_segundos, 60.0)) / 3600000.0 AS kwh_solar,
            SUM(COALESCE(d.potencia_activa_salida_w, 0) * LEAST(d.delta_segundos, 60.0)) / 3600000.0 AS kwh_carga,
            SUM(COALESCE(d.potencia_red_w, 0) * LEAST(d.delta_segundos, 60.0)) / 3600000.0 AS kwh_red,
            SUM(COALESCE(d.potencia_bateria_w, 0) * LEAST(d.delta_segundos, 60.0)) / 3600000.0 AS kwh_bateria,
            COUNT(*) AS total_filas,
            SUM(LEAST(d.delta_segundos, 60.0)) AS segundos_totales
        FROM lecturas_con_delta d
        WHERE d.delta_segundos IS NOT NULL
        GROUP BY d.inversor_id
    )
    SELECT 
        i.inversor_id,
        ROUND(i.kwh_solar::NUMERIC, 3),
        ROUND(i.kwh_carga::NUMERIC, 3),
        ROUND(i.kwh_red::NUMERIC, 3),
        ROUND(i.kwh_bateria::NUMERIC, 3),
        i.total_filas,
        ROUND((i.segundos_totales / NULLIF(EXTRACT(EPOCH FROM (p_fecha_fin - p_fecha_inicio)), 0) * 100.0)::NUMERIC, 2)
    FROM integracion i;
END;
$$;

COMMENT ON FUNCTION telemetria.fn_calcular_energia_kwh(INT, TIMESTAMPTZ, TIMESTAMPTZ) IS 
'Realiza integración numérica trapezoidal de potencia instantánea sobre el intervalo temporal para obtener balances de energía en kWh.';

-- ============================================================================
-- SECCIÓN B: DEFINICIÓN DE TRIGGERS
-- ============================================================================

-- ----------------------------------------------------------------------------
-- B.1 Trigger de Disparo de Alarmas en Telemetría
-- ----------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_evaluar_alarmas_telemetria ON telemetria.lecturas;
CREATE TRIGGER trg_evaluar_alarmas_telemetria
    AFTER INSERT ON telemetria.lecturas
    FOR EACH ROW
    EXECUTE FUNCTION operacion.fn_evaluar_alertas_telemetria();

-- ----------------------------------------------------------------------------
-- B.2 Triggers de Auditoría en Tablas Críticas del Sistema
-- ----------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_auditar_inversores ON microrred.inversores;
CREATE TRIGGER trg_auditar_inversores
    AFTER INSERT OR UPDATE OR DELETE ON microrred.inversores
    FOR EACH ROW
    EXECUTE FUNCTION auditoria.fn_auditar_modificaciones();

DROP TRIGGER IF EXISTS trg_auditar_umbrales ON operacion.umbrales_configuracion;
CREATE TRIGGER trg_auditar_umbrales
    AFTER INSERT OR UPDATE OR DELETE ON operacion.umbrales_configuracion
    FOR EACH ROW
    EXECUTE FUNCTION auditoria.fn_auditar_modificaciones();

DROP TRIGGER IF EXISTS trg_auditar_tipos_alarma ON operacion.catalogo_tipos_alarma;
CREATE TRIGGER trg_auditar_tipos_alarma
    AFTER INSERT OR UPDATE OR DELETE ON operacion.catalogo_tipos_alarma
    FOR EACH ROW
    EXECUTE FUNCTION auditoria.fn_auditar_modificaciones();

-- Auditar únicamente modificaciones y eliminaciones en telemetría (prevención de borrado fraudulento)
DROP TRIGGER IF EXISTS trg_auditar_telemetria_modificaciones ON telemetria.lecturas;
CREATE TRIGGER trg_auditar_telemetria_modificaciones
    AFTER UPDATE OR DELETE ON telemetria.lecturas
    FOR EACH ROW
    EXECUTE FUNCTION auditoria.fn_auditar_modificaciones();

-- ----------------------------------------------------------------------------
-- B.3 Trigger de Protección de Datos Personales (Ley 1581)
-- ----------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_sanitizar_contexto_habeas_data ON operacion.registros_contexto;
CREATE TRIGGER trg_sanitizar_contexto_habeas_data
    BEFORE INSERT OR UPDATE ON operacion.registros_contexto
    FOR EACH ROW
    EXECUTE FUNCTION operacion.fn_sanitizar_contexto_habeas_data();

-- ============================================================================
-- SECCIÓN C: PROCEDIMIENTOS ALMACENADOS (STORED PROCEDURES)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- C.1 Procedimiento: Gestión y Resolución del Ciclo de Vida de una Alarma
-- ----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE operacion.sp_gestionar_estado_alarma(
    p_alarma_id BIGINT,
    p_nuevo_estado operacion.estado_alarma,
    p_comentario TEXT,
    p_usuario VARCHAR(100) DEFAULT CURRENT_USER
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_estado_actual operacion.estado_alarma;
BEGIN
    -- Validar existencia de la alarma
    SELECT estado INTO v_estado_actual
    FROM operacion.alarmas
    WHERE id = p_alarma_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No se encontró la alarma con identificador %', p_alarma_id;
    END IF;

    -- Validar transiciones de estado permitidas
    IF v_estado_actual IN ('RESUELTA', 'DESCARTADA') THEN
        RAISE EXCEPTION 'La alarma % ya se encuentra cerrada (Estado: %). No se admiten cambios.', p_alarma_id, v_estado_actual;
    END IF;

    -- Aplicar transición de estado
    IF p_nuevo_estado IN ('RESUELTA', 'DESCARTADA') THEN
        UPDATE operacion.alarmas
        SET estado = p_nuevo_estado,
            fecha_resolucion = CURRENT_TIMESTAMP,
            usuario_resolutor = p_usuario,
            comentario_resolucion = p_comentario
        WHERE id = p_alarma_id;
    ELSE
        UPDATE operacion.alarmas
        SET estado = p_nuevo_estado,
            comentario_resolucion = COALESCE(comentario_resolucion || E'\n' || p_comentario, p_comentario)
        WHERE id = p_alarma_id;
    END IF;

    RAISE NOTICE 'Alarma % actualizada exitosamente a estado: % por usuario %', p_alarma_id, p_nuevo_estado, p_usuario;
END;
$$;

COMMENT ON PROCEDURE operacion.sp_gestionar_estado_alarma(BIGINT, operacion.estado_alarma, TEXT, VARCHAR) IS 
'Controla la máquina de estados de las alarmas operativas garantizando trazabilidad y registro del operador responsable.';

-- ----------------------------------------------------------------------------
-- C.2 Procedimiento: Resolución Masiva de Alarmas Normalizadas
-- ----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE operacion.sp_resolver_alarmas_masivas(
    p_inversor_id INT,
    p_tipo_alarma_id INT,
    p_usuario VARCHAR(100) DEFAULT CURRENT_USER,
    p_comentario TEXT DEFAULT 'Cierre masivo de alarma tras normalización de telemetría y verificación de variables.'
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_afectadas INT;
BEGIN
    UPDATE operacion.alarmas
    SET estado = 'RESUELTA',
        fecha_resolucion = CURRENT_TIMESTAMP,
        usuario_resolutor = p_usuario,
        comentario_resolucion = p_comentario
    WHERE inversor_id = p_inversor_id
      AND tipo_alarma_id = p_tipo_alarma_id
      AND estado IN ('ACTIVA', 'EN_REVISION');

    GET DIAGNOSTICS v_afectadas = ROW_COUNT;
    RAISE NOTICE 'Se resolvieron % alarmas activas del tipo % para el inversor %.', v_afectadas, p_tipo_alarma_id, p_inversor_id;
END;
$$;

COMMENT ON PROCEDURE operacion.sp_resolver_alarmas_masivas(INT, INT, VARCHAR, TEXT) IS 
'Cierra de forma segura un conjunto de alarmas abiertas de un tipo específico una vez corregida la contingencia física.';

-- ----------------------------------------------------------------------------
-- C.3 Procedimiento: Consolidación Diaria de Incidentes y Alarmas
-- ----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE operacion.sp_consolidar_resumen_diario_alarmas(
    p_fecha DATE
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_inv RECORD;
BEGIN
    FOR v_inv IN SELECT id FROM microrred.inversores LOOP
        INSERT INTO operacion.resumen_diario_alarmas (
            fecha, inversor_id, total_alarmas, total_criticas, total_advertencias,
            total_informativas, tiempo_promedio_resolucion_min, fecha_generacion
        )
        SELECT 
            p_fecha,
            v_inv.id,
            COUNT(*),
            COUNT(*) FILTER (WHERE severidad = 'CRITICAL'),
            COUNT(*) FILTER (WHERE severidad = 'WARNING'),
            COUNT(*) FILTER (WHERE severidad = 'INFO'),
            ROUND(AVG(EXTRACT(EPOCH FROM (fecha_resolucion - fecha_deteccion)) / 60.0)::NUMERIC, 2),
            CURRENT_TIMESTAMP
        FROM operacion.alarmas
        WHERE inversor_id = v_inv.id
          AND fecha_deteccion::DATE = p_fecha
        ON CONFLICT (fecha, inversor_id) DO UPDATE SET 
            total_alarmas = EXCLUDED.total_alarmas,
            total_criticas = EXCLUDED.total_criticas,
            total_advertencias = EXCLUDED.total_advertencias,
            total_informativas = EXCLUDED.total_informativas,
            tiempo_promedio_resolucion_min = EXCLUDED.tiempo_promedio_resolucion_min,
            fecha_generacion = CURRENT_TIMESTAMP;
    END LOOP;

    RAISE NOTICE 'Resumen diario de alarmas consolidado con éxito para la fecha: %', p_fecha;
END;
$$;

COMMENT ON PROCEDURE operacion.sp_consolidar_resumen_diario_alarmas(DATE) IS 
'Genera agregaciones diarias de incidentes por subsistema para informes ejecutivos y KPI de mantenimiento.';

-- ----------------------------------------------------------------------------
-- C.4 Procedimiento: Purga Controlada de Auditoría Histórica con Bitácora
-- ----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE auditoria.sp_purgar_auditoria_historica(
    p_dias_retencion INT,
    p_usuario_autorizador VARCHAR(100) DEFAULT CURRENT_USER
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_fecha_corte TIMESTAMPTZ;
    v_filas_eliminadas BIGINT;
BEGIN
    IF p_dias_retencion < 30 THEN
        RAISE EXCEPTION 'Por políticas de cumplimiento normativo (Ley 1581 / ISO 27001), el periodo de retención no puede ser inferior a 30 días.';
    END IF;

    v_fecha_corte := CURRENT_TIMESTAMP - (p_dias_retencion || ' days')::INTERVAL;

    DELETE FROM auditoria.registro_cambios
    WHERE fecha_hora < v_fecha_corte;

    GET DIAGNOSTICS v_filas_eliminadas = ROW_COUNT;

    -- Dejar constancia del mantenimiento en la propia auditoría
    INSERT INTO auditoria.registro_cambios (
        usuario_bd, accion, esquema_nombre, tabla_nombre, registro_id,
        datos_nuevos, ip_cliente, aplicacion_cliente
    ) VALUES (
        p_usuario_autorizador,
        'DELETE',
        'auditoria',
        'registro_cambios',
        'PURGA_MANTENIMIENTO',
        jsonb_build_object(
            'evento', 'Purga periódica de registros antiguos',
            'filas_purgadas', v_filas_eliminadas,
            'fecha_corte', v_fecha_corte,
            'dias_retencion', p_dias_retencion
        ),
        inet_client_addr(),
        'sp_purgar_auditoria_historica'
    );

    RAISE NOTICE 'Purga de auditoría completada: % filas eliminadas anteriores a % por orden de %.',
                 v_filas_eliminadas, v_fecha_corte, p_usuario_autorizador;
END;
$$;

COMMENT ON PROCEDURE auditoria.sp_purgar_auditoria_historica(INT, VARCHAR) IS 
'Depuración controlada de bitácora antigua con cumplimiento de políticas de retención y auto-registro forense.';
