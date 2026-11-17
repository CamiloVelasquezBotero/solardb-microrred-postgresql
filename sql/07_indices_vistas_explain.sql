-- ============================================================================
-- INSTITUCIÓN UNIVERSITARIA PASCUAL BRAVO
-- Departamento de Sistemas Digitales · Bases de Datos I · Grupo 811
-- Taller 6 · SolarDB: Base de Datos para la Telemetría de una Microrred Híbrida
-- Línea 5: SolarDB: Funciones, Procedimientos y Triggers en PL/pgSQL
--          para Alarmas y Auditoría
-- ============================================================================
-- Archivo: sql/07_indices_vistas_explain.sql
-- Propósito: Creación de índices optimizados con justificación analítica,
--            vistas operativas de negocio y evidencia de rendimiento con EXPLAIN.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. CREACIÓN DE ÍNDICES OPTIMIZADOS Y JUSTIFICADOS
-- ----------------------------------------------------------------------------

-- 1.1 Índice B-Tree Compuesto Principal de Telemetría
-- Justificación: Es la columna vertebral de las consultas de series de tiempo.
-- Permite búsquedas por rango de fecha filtradas por inversor mediante Index Scan
-- en lugar de recorrer secuencialmente más de un millón de registros.
CREATE INDEX IF NOT EXISTS idx_lecturas_inversor_fecha 
ON telemetria.lecturas (inversor_id, fecha_hora DESC);

COMMENT ON INDEX telemetria.idx_lecturas_inversor_fecha IS 
'Optimiza filtros por rango temporal por inversor (Consultas 1, 2, 3 y cálculo de energía).';

-- 1.2 Índice Parcial B-Tree para Batería Baja
-- Justificación: La gran mayoría de lecturas tienen SoC > 20%. Un índice parcial
-- que indexe únicamente filas con soc_bateria_pct <= 20 ocupa menos del 2% del espacio
-- en disco y memoria RAM, permitiendo resolver la Consulta 4 en sub-milisegundos.
CREATE INDEX IF NOT EXISTS idx_lecturas_soc_bajo_parcial 
ON telemetria.lecturas (fecha_hora, inversor_id, soc_bateria_pct) 
WHERE soc_bateria_pct <= 20;

COMMENT ON INDEX telemetria.idx_lecturas_soc_bajo_parcial IS 
'Índice parcial de alto rendimiento para monitoreo de descarga profunda de baterías.';

-- 1.3 Índice GIN con jsonb_path_ops en Registros de Contexto
-- Justificación: Acelera búsquedas de contención (@>) en atributos JSONB de tareas
-- de cómputo, dispositivos y comandos (Consulta 6).
CREATE INDEX IF NOT EXISTS idx_contexto_payload_gin 
ON operacion.registros_contexto USING gin (payload_json jsonb_path_ops);

COMMENT ON INDEX operacion.idx_contexto_payload_gin IS 
'Índice GIN para búsquedas estructuradas de alta velocidad en atributos JSONB.';

-- 1.4 Índice B-Tree Compuesto en Alarmas Activas
-- Justificación: Proporciona Index Only Scan para el tablero de control de incidentes
-- filtrando rápidamente por estado (ACTIVA, EN_REVISION).
CREATE INDEX IF NOT EXISTS idx_alarmas_estado_fecha 
ON operacion.alarmas (estado, fecha_deteccion DESC) 
INCLUDE (inversor_id, severidad, tipo_alarma_id);

COMMENT ON INDEX operacion.idx_alarmas_estado_fecha IS 
'Optimiza la visualización del tablero de incidentes activos y KPI de mantenimiento.';

-- 1.5 Índice B-Tree en Auditoría por Tabla y Fecha
-- Justificación: Permite auditorías forenses instantáneas sobre una entidad específica.
CREATE INDEX IF NOT EXISTS idx_auditoria_tabla_fecha 
ON auditoria.registro_cambios (tabla_nombre, fecha_hora DESC);

COMMENT ON INDEX auditoria.idx_auditoria_tabla_fecha IS 
'Acelera la inspección forense de cambios por tabla en el esquema de auditoría.';

-- ----------------------------------------------------------------------------
-- 2. VISTAS ÚTILES PARA EL NEGOCIO (SECCIÓN 4.E)
-- ----------------------------------------------------------------------------

-- 2.1 Vista de Negocio 1: Balance Energético y Potencia Horaria Consolidada
-- Propósito: Entrega un resumen horario listo para tableros de supervisión y BI,
-- integrando potencia en kWh, factor de carga promedio y estado de la red.
CREATE OR REPLACE VIEW telemetria.v_balance_energetico_horario AS
SELECT 
    l.inversor_id,
    sub.nombre AS subsistema,
    DATE_TRUNC('hour', l.fecha_hora) AS fecha_hora_bloque,
    ROUND(AVG(l.potencia_pv_w)::NUMERIC, 2) AS potencia_solar_promedio_w,
    ROUND(MAX(l.potencia_pv_w)::NUMERIC, 2) AS potencia_solar_maxima_w,
    ROUND(AVG(l.potencia_activa_salida_w)::NUMERIC, 2) AS potencia_carga_promedio_w,
    ROUND(AVG(l.potencia_red_w)::NUMERIC, 2) AS potencia_red_promedio_w,
    ROUND(AVG(l.soc_bateria_pct)::NUMERIC, 1) AS soc_promedio_pct,
    ROUND(AVG(l.porcentaje_carga_pct)::NUMERIC, 1) AS porcentaje_carga_promedio_pct,
    ROUND(AVG(l.temperatura_inversor_1_c)::NUMERIC, 1) AS temp_promedio_inversor_c,
    COUNT(*) AS lecturas_en_la_hora,
    -- Estimación de energía integrada en la hora (Wh / 1000 = kWh)
    ROUND((AVG(COALESCE(l.potencia_pv_w, 0)) / 1000.0)::NUMERIC, 3) AS energia_solar_kwh,
    ROUND((AVG(COALESCE(l.potencia_activa_salida_w, 0)) / 1000.0)::NUMERIC, 3) AS energia_carga_kwh,
    ROUND((AVG(COALESCE(l.potencia_red_w, 0)) / 1000.0)::NUMERIC, 3) AS energia_red_kwh
FROM telemetria.lecturas l
JOIN microrred.inversores i ON i.id = l.inversor_id
JOIN microrred.subsistemas sub ON sub.id = i.subsistema_id
GROUP BY l.inversor_id, sub.nombre, DATE_TRUNC('hour', l.fecha_hora);

COMMENT ON VIEW telemetria.v_balance_energetico_horario IS 
'Vista analítica que agrega las lecturas de telemetría a nivel horario para reportes de balance energético.';

-- 2.2 Vista de Negocio 2: Tablero de Control de Alarmas e Incidentes en Tiempo Real
-- Propósito: Centro de despacho y supervisión para operadores en DBeaver. Muestra
-- todas las alarmas abiertas, tiempo transcurrido desde la detección, ubicación física
-- y recomendación técnica de actuación.
CREATE OR REPLACE VIEW operacion.v_tablero_control_alarmas AS
SELECT 
    a.id AS alarma_id,
    a.fecha_deteccion,
    ROUND((EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - a.fecha_deteccion)) / 60.0)::NUMERIC, 1) AS minutos_activa,
    a.inversor_id,
    sub.nombre AS subsistema,
    i.descripcion_ubicacion,
    a.severidad,
    t.codigo AS codigo_alarma,
    t.nombre AS tipo_alarma,
    a.parametro,
    a.valor_detectado,
    a.umbral_disparado,
    a.mensaje_alarma,
    t.accion_recomendada,
    a.estado,
    a.usuario_resolutor
FROM operacion.alarmas a
JOIN operacion.catalogo_tipos_alarma t ON t.id = a.tipo_alarma_id
JOIN microrred.inversores i ON i.id = a.inversor_id
JOIN microrred.subsistemas sub ON sub.id = i.subsistema_id
WHERE a.estado IN ('ACTIVA', 'EN_REVISION')
ORDER BY 
    CASE a.severidad 
        WHEN 'CRITICAL' THEN 1 
        WHEN 'WARNING' THEN 2 
        WHEN 'INFO' THEN 3 
    END ASC,
    a.fecha_deteccion DESC;

COMMENT ON VIEW operacion.v_tablero_control_alarmas IS 
'Tablero en tiempo real de alarmas abiertas ordenadas por severidad con acciones recomendadas.';

-- ----------------------------------------------------------------------------
-- 3. EVIDENCIA DE EFECTO DE LOS ÍNDICES (EXPLAIN ANALYZE)
-- ----------------------------------------------------------------------------

-- Prueba 1: Filtrado de rango temporal en más de 1 millón de registros
-- Con idx_lecturas_inversor_fecha: Utiliza Index Scan / Bitmap Index Scan
EXPLAIN (ANALYZE, BUFFERS, COSTS)
SELECT fecha_hora, potencia_pv_w, potencia_activa_salida_w, soc_bateria_pct
FROM telemetria.lecturas
WHERE inversor_id = 1 
  AND fecha_hora >= '2025-07-20 00:00:00+00' 
  AND fecha_hora < '2025-07-21 00:00:00+00'
ORDER BY fecha_hora ASC;

-- Prueba 2: Búsqueda de lecturas con SoC bajo (< 20%)
-- Con idx_lecturas_soc_bajo_parcial: Utiliza Bitmap Index Scan parcial
EXPLAIN (ANALYZE, BUFFERS, COSTS)
SELECT fecha_hora, inversor_id, soc_bateria_pct, tension_bateria_v
FROM telemetria.lecturas
WHERE soc_bateria_pct <= 20
  AND fecha_hora >= '2025-07-14 00:00:00+00'
ORDER BY fecha_hora ASC;

-- Prueba 3: Búsqueda en JSONB de contexto con índice GIN
-- Con idx_contexto_payload_gin: Utiliza Bitmap Index Scan en el índice GIN
EXPLAIN (ANALYZE, BUFFERS, COSTS)
SELECT id, fecha_inicio, payload_json->>'device' AS dispositivo
FROM operacion.registros_contexto
WHERE payload_json @> '{"task_type": "CNN fitting, GPU load"}';
