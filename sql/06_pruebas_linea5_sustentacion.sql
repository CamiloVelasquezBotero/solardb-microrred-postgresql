-- ============================================================================
-- INSTITUCIÓN UNIVERSITARIA PASCUAL BRAVO
-- Departamento de Sistemas Digitales · Bases de Datos I · Grupo 811
-- Taller 6 · SolarDB: Base de Datos para la Telemetría de una Microrred Híbrida
-- Línea 5: SolarDB: Funciones, Procedimientos y Triggers en PL/pgSQL
--          para Alarmas y Auditoría
-- ============================================================================
-- Archivo: sql/06_pruebas_linea5_sustentacion.sql
-- Propósito: Casos de prueba interactivos y verificables en vivo para la
--            sustentación ante el docente en DBeaver o psql:
--   1. Prueba de disparo automático de alarmas por trigger.
--   2. Prueba de auditoría Change Data Capture (CDC) en JSONB.
--   3. Prueba de procedimientos almacenados y ciclo de vida de alarmas.
--   4. Prueba de sanitización automática de datos personales (Ley 1581 de 2012).
--   5. Prueba de rechazo de transacciones por violación de restricciones CHECK y FK.
--   6. Prueba de cálculo de balance energético mediante función PL/pgSQL.
-- ============================================================================

-- ============================================================================
-- INICIANDO BATERÍA DE PRUEBAS DE SUSTENTACIÓN · SOLARDB LÍNEA 5       
-- ============================================================================

-- Limpieza preventiva para garantizar idempotencia y reejecución limpia
DELETE FROM operacion.alarmas WHERE fecha_deteccion IN ('2026-03-15 10:00:00+00', '2026-03-15 10:15:00+00');
DELETE FROM telemetria.lecturas WHERE fecha_hora IN ('2026-03-15 10:00:00+00', '2026-03-15 10:15:00+00');
DELETE FROM operacion.registros_contexto WHERE id = 999999;

-- ----------------------------------------------------------------------------
-- CASO 1: Inserción de lectura normal (Sin disparo de alarmas)
-- ----------------------------------------------------------------------------
-- --- CASO 1: Inserción de telemetría nominal ---
INSERT INTO telemetria.lecturas (
    inversor_id, fecha_hora, read_ts_unix,
    tension_bateria_v, corriente_bateria_a, potencia_bateria_w, soc_bateria_pct,
    tension_pv_v, corriente_pv_a, potencia_pv_w,
    tension_salida_v, corriente_salida_a, frecuencia_salida_hz, potencia_activa_salida_w, potencia_aparente_salida_va, porcentaje_carga_pct,
    tension_red_v, corriente_red_a, frecuencia_red_hz, potencia_red_w,
    temperatura_inversor_1_c, temperatura_inversor_2_c, temperatura_bateria_c, temperatura_ambiente_c
) VALUES (
    1, '2026-03-15 10:00:00+00', 1773568800.0,
    53.20, 10.50, 558.60, 80,
    385.00, 12.00, 4620.00,
    220.00, 14.50, 50.00, 3100.00, 3190.00, 39,
    220.00, 0.00, 50.00, 0.00,
    42.00, 40.00, 30.00, 26.00
);

-- Verificar que NO se crearon alarmas
SELECT COUNT(*) AS alarmas_creadas_caso1
FROM operacion.alarmas
WHERE fecha_deteccion = '2026-03-15 10:00:00+00';

-- ----------------------------------------------------------------------------
-- CASO 2: Inserción de lectura crítica anómala (Disparo automático de Alarmas)
-- ----------------------------------------------------------------------------
-- --- CASO 2: Inserción anómala (SoC = 8%, Temp = 62.5 °C, Vbat = 43.2 V) ---
INSERT INTO telemetria.lecturas (
    inversor_id, fecha_hora, read_ts_unix,
    tension_bateria_v, corriente_bateria_a, potencia_bateria_w, soc_bateria_pct,
    tension_pv_v, corriente_pv_a, potencia_pv_w,
    tension_salida_v, corriente_salida_a, frecuencia_salida_hz, potencia_activa_salida_w, potencia_aparente_salida_va, porcentaje_carga_pct,
    tension_red_v, corriente_red_a, frecuencia_red_hz, potencia_red_w,
    temperatura_inversor_1_c, temperatura_inversor_2_c, temperatura_bateria_c, temperatura_ambiente_c
) VALUES (
    1, '2026-03-15 10:15:00+00', 1773569700.0,
    43.20, 95.00, 4104.00, 8, -- Tensión baja (<44V) y SoC crítico (<10%)
    0.00, 0.00, 0.00,
    215.00, 32.00, 49.90, 6800.00, 6880.00, 85,
    0.00, 0.00, 0.00, 0.00, -- Pérdida de red (Modo isla)
    62.50, 58.00, 41.00, 32.00 -- Sobrecalentamiento (>60°C)
);

-- Verificar las alarmas generadas automáticamente por el trigger
SELECT 
    id, inversor_id, tipo_alarma_id, severidad, parametro, valor_detectado,
    umbral_disparado, estado, mensaje_alarma
FROM operacion.alarmas
WHERE fecha_deteccion = '2026-03-15 10:15:00+00';

-- ----------------------------------------------------------------------------
-- CASO 3: Modificación de Configuración y Verificación de Auditoría CDC
-- ----------------------------------------------------------------------------
-- --- CASO 3: Auditoría CDC al modificar umbrales operativos ---
-- Modificar un umbral en operacion.umbrales_configuracion
UPDATE operacion.umbrales_configuracion
SET umbral_warning = 25.00,
    umbral_critical = 12.00,
    modificado_por = 'ingeniero_operaciones'
WHERE inversor_id = 1 AND tipo_alarma_id = 1;

-- Verificar la captura automática en auditoria.registro_cambios
SELECT 
    id, fecha_hora, usuario_bd, accion, esquema_nombre, tabla_nombre,
    registro_id, diferencias, aplicacion_cliente
FROM auditoria.registro_cambios
WHERE tabla_nombre = 'umbrales_configuracion'
ORDER BY id DESC
LIMIT 1;

-- ----------------------------------------------------------------------------
-- CASO 4: Procedimiento Almacenado: Gestión de Estado y Resolución de Alarma
-- ----------------------------------------------------------------------------
-- --- CASO 4: Resolución de alarma mediante procedimiento almacenado ---
DO $$
DECLARE
    v_alarma_id BIGINT;
BEGIN
    SELECT id INTO v_alarma_id
    FROM operacion.alarmas
    WHERE fecha_deteccion = '2026-03-15 10:15:00+00'
    LIMIT 1;

    -- Llamar al procedimiento almacenado para pasar a EN_REVISION
    CALL operacion.sp_gestionar_estado_alarma(
        v_alarma_id,
        'EN_REVISION'::operacion.estado_alarma,
        'Técnico en sitio revisando flujo de aire y nivel de carga de baterías.',
        'camilo_operador'
    );

    -- Llamar al procedimiento almacenado para marcar como RESUELTA
    CALL operacion.sp_gestionar_estado_alarma(
        v_alarma_id,
        'RESUELTA'::operacion.estado_alarma,
        'Incidente solucionado: Ventilador auxiliar activado y carga transferida a red comercial.',
        'camilo_operador'
    );
END $$;

-- Verificar estado final de la alarma
SELECT 
    id, estado, fecha_resolucion, usuario_resolutor, comentario_resolucion
FROM operacion.alarmas
WHERE fecha_deteccion = '2026-03-15 10:15:00+00'
LIMIT 1;

-- ----------------------------------------------------------------------------
-- CASO 5: Protección de Datos Personales (Trigger Habeas Data - Ley 1581)
-- ----------------------------------------------------------------------------
-- --- CASO 5: Sanitización automática de datos personales en contexto ---
INSERT INTO operacion.registros_contexto (
    id, fecha_registro, fecha_inicio, fecha_fin, inversor_id,
    origen, dispositivo, tipo_tarea, descripcion_textual, payload_json
) VALUES (
    999999, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP + INTERVAL '1 hour', 1,
    'workstation1_log', 'workstation1', 'Deep Learning Model Training',
    'Entrenamiento ejecutado por el usuario juan.perez@pascualbravo.edu.co en el laboratorio.',
    jsonb_build_object(
        'device', 'workstation1',
        'directory', 'C:\Users\juan_perez\workspace\modelo_red_neuronal',
        'command', 'python train.py --token secret_xyz_987 --epochs 100'
    )
);

-- Verificar que el trigger sanitizó la ruta, el comando y el correo
SELECT 
    id, descripcion_textual, payload_json->>'directory' AS directorio_sanitizado,
    payload_json->>'command' AS comando_sanitizado, datos_personales_anonimizados
FROM operacion.registros_contexto
WHERE id = 999999;

-- ----------------------------------------------------------------------------
-- CASO 6: Prueba de Rechazo: Violación de Restricción CHECK
-- ----------------------------------------------------------------------------
-- --- CASO 6: Rechazo controlado de datos imposibles (CHECK Violation) ---
DO $$
BEGIN
    INSERT INTO telemetria.lecturas (
        inversor_id, fecha_hora, read_ts_unix, tension_bateria_v, soc_bateria_pct
    ) VALUES (
        1, '2026-03-15 11:00:00+00', 1773572400.0, 52.00, 185 -- Imposible: SoC > 100%
    );
    RAISE EXCEPTION 'FALLÓ LA PRUEBA: El motor debió rechazar el SoC de 185%%.';
EXCEPTION
    WHEN check_violation THEN
        RAISE NOTICE '[ÉXITO] La base de datos rechazó la tupla por violación de chk_telemetria_soc (SoC no puede ser > 100%%).';
END $$;

-- ----------------------------------------------------------------------------
-- CASO 7: Prueba de Función PL/pgSQL: Cálculo Numérico de Energía
-- ----------------------------------------------------------------------------
-- --- CASO 7: Ejecución de función de cálculo de energía (kWh) ---
SELECT * FROM telemetria.fn_calcular_energia_kwh(
    1,
    '2025-07-14 00:00:00+00',
    '2025-07-15 00:00:00+00'
);

-- ======================================================================
-- BATERÍA DE PRUEBAS COMPLETADA EXITOSAMENTE                           
-- ======================================================================
