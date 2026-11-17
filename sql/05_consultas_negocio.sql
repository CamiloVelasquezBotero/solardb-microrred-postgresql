-- ============================================================================
-- INSTITUCIÓN UNIVERSITARIA PASCUAL BRAVO
-- Departamento de Sistemas Digitales · Bases de Datos I · Grupo 811
-- Taller 6 · SolarDB: Base de Datos para la Telemetría de una Microrred Híbrida
-- Línea 5: SolarDB: Funciones, Procedimientos y Triggers en PL/pgSQL
--          para Alarmas y Auditoría
-- ============================================================================
-- Archivo: sql/05_consultas_negocio.sql
-- Propósito: Diez (10) consultas analíticas y de negocio obligatorias y avanzadas
--            utilizando JOINs, funciones de agregación, GROUP BY / HAVING,
--            funciones de ventana (WINDOW FUNCTIONS), subconsultas, CTEs,
--            rangos temporales y operadores nativos de JSONB.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- CONSULTA 1: Energía solar generada, energía entregada a la carga y energía
--             tomada de la red, por inversor, por día y por mes.
-- ----------------------------------------------------------------------------
-- Técnica: CTE con función de ventana LAG() para cálculo de delta temporal (dt)
--          e integración trapezoidal de potencia activa instantánea a kWh.
WITH deltas_temporales AS (
    SELECT 
        l.inversor_id,
        l.fecha_hora,
        DATE_TRUNC('month', l.fecha_hora) AS mes,
        l.fecha_hora::DATE AS dia,
        l.potencia_pv_w,
        l.potencia_activa_salida_w,
        l.potencia_red_w,
        -- Delta de tiempo entre lecturas consecutivas (limitado a máx 60s para no sobre-estimar en paradas)
        LEAST(EXTRACT(EPOCH FROM (l.fecha_hora - LAG(l.fecha_hora) OVER (PARTITION BY l.inversor_id ORDER BY l.fecha_hora))), 60.0) AS dt_segundos
    FROM telemetria.lecturas l
    WHERE l.fecha_hora >= '2025-07-14 00:00:00+00' AND l.fecha_hora < '2025-08-14 00:00:00+00'
),
energia_diaria AS (
    SELECT 
        d.mes,
        d.dia,
        d.inversor_id,
        i.descripcion_ubicacion,
        sub.nombre AS subsistema,
        -- Integración: Potencia (W) * dt (s) / 3,600,000 = kWh
        ROUND(SUM(COALESCE(d.potencia_pv_w, 0) * d.dt_segundos / 3600000.0)::NUMERIC, 2) AS energia_solar_generada_kwh,
        ROUND(SUM(COALESCE(d.potencia_activa_salida_w, 0) * d.dt_segundos / 3600000.0)::NUMERIC, 2) AS energia_entregada_carga_kwh,
        ROUND(SUM(COALESCE(d.potencia_red_w, 0) * d.dt_segundos / 3600000.0)::NUMERIC, 2) AS energia_tomada_red_kwh,
        COUNT(*) AS total_lecturas_dia
    FROM deltas_temporales d
    JOIN microrred.inversores i ON i.id = d.inversor_id
    JOIN microrred.subsistemas sub ON sub.id = i.subsistema_id
    WHERE d.dt_segundos IS NOT NULL
    GROUP BY d.mes, d.dia, d.inversor_id, i.descripcion_ubicacion, sub.nombre
)
SELECT 
    TO_CHAR(mes, 'YYYY-MM') AS mes,
    dia,
    inversor_id,
    subsistema,
    energia_solar_generada_kwh,
    energia_entregada_carga_kwh,
    energia_tomada_red_kwh,
    -- Porcentaje de cobertura solar de la carga
    ROUND((energia_solar_generada_kwh / NULLIF(energia_entregada_carga_kwh, 0) * 100.0)::NUMERIC, 2) AS autosuficiencia_solar_pct,
    total_lecturas_dia
FROM energia_diaria
ORDER BY dia ASC, inversor_id ASC
LIMIT 30;

-- ----------------------------------------------------------------------------
-- CONSULTA 2: Hora del día con mayor generación solar promedio, por inversor
--             y por mes.
-- ----------------------------------------------------------------------------
-- Técnica: Agrupación temporal con EXTRACT(HOUR), RANK() sobre potencia promedio
--          y filtrado de la hora pico por mes.
WITH generacion_horaria AS (
    SELECT 
        l.inversor_id,
        sub.nombre AS subsistema,
        TO_CHAR(l.fecha_hora, 'YYYY-MM') AS anio_mes,
        EXTRACT(HOUR FROM l.fecha_hora) AS hora_del_dia,
        ROUND(AVG(l.potencia_pv_w)::NUMERIC, 2) AS potencia_solar_promedio_w,
        ROUND(MAX(l.potencia_pv_w)::NUMERIC, 2) AS potencia_solar_pico_w,
        COUNT(*) AS total_muestras
    FROM telemetria.lecturas l
    JOIN microrred.inversores i ON i.id = l.inversor_id
    JOIN microrred.subsistemas sub ON sub.id = i.subsistema_id
    WHERE l.potencia_pv_w > 0
    GROUP BY l.inversor_id, sub.nombre, TO_CHAR(l.fecha_hora, 'YYYY-MM'), EXTRACT(HOUR FROM l.fecha_hora)
),
ranking_horas AS (
    SELECT 
        *,
        DENSE_RANK() OVER (PARTITION BY inversor_id, anio_mes ORDER BY potencia_solar_promedio_w DESC) AS rnk
    FROM generacion_horaria
)
SELECT 
    anio_mes,
    inversor_id,
    subsistema,
    hora_del_dia AS hora_pico_solar,
    potencia_solar_promedio_w,
    potencia_solar_pico_w,
    total_muestras
FROM ranking_horas
WHERE rnk = 1
ORDER BY anio_mes ASC, inversor_id ASC;

-- ----------------------------------------------------------------------------
-- CONSULTA 3: Comparación multidimensional entre los dos inversores en un
--             mismo periodo (Cómputo Científico vs Climatización HVAC).
-- ----------------------------------------------------------------------------
-- Técnica: CASE condicional, agregaciones comparativas, ratio de utilización
--          y factor de carga promedio.
SELECT 
    DATE_TRUNC('week', l.fecha_hora)::DATE AS semana_inicio,
    -- Métricas Inversor 1 (Cómputo)
    ROUND(AVG(CASE WHEN l.inversor_id = 1 THEN l.potencia_activa_salida_w END)::NUMERIC, 2) AS p_prom_carga_inv1_computo_w,
    ROUND(AVG(CASE WHEN l.inversor_id = 1 THEN l.porcentaje_carga_pct END)::NUMERIC, 1) AS factor_carga_inv1_pct,
    ROUND(AVG(CASE WHEN l.inversor_id = 1 THEN l.temperatura_inversor_1_c END)::NUMERIC, 1) AS temp_prom_inv1_c,
    
    -- Métricas Inversor 2 (Climatización HVAC)
    ROUND(AVG(CASE WHEN l.inversor_id = 2 THEN l.potencia_activa_salida_w END)::NUMERIC, 2) AS p_prom_carga_inv2_hvac_w,
    ROUND(AVG(CASE WHEN l.inversor_id = 2 THEN l.porcentaje_carga_pct END)::NUMERIC, 1) AS factor_carga_inv2_pct,
    ROUND(AVG(CASE WHEN l.inversor_id = 2 THEN l.temperatura_inversor_1_c END)::NUMERIC, 1) AS temp_prom_inv2_c,
    
    -- Diferencial de demanda
    ROUND((AVG(CASE WHEN l.inversor_id = 1 THEN l.potencia_activa_salida_w END) - 
           AVG(CASE WHEN l.inversor_id = 2 THEN l.potencia_activa_salida_w END))::NUMERIC, 2) AS diferencial_demanda_w
FROM telemetria.lecturas l
WHERE l.fecha_hora >= '2025-07-14 00:00:00+00' AND l.fecha_hora < '2025-08-31 23:59:59+00'
GROUP BY DATE_TRUNC('week', l.fecha_hora)::DATE
ORDER BY semana_inicio ASC;

-- ----------------------------------------------------------------------------
-- CONSULTA 4: Número de lecturas con batería por debajo del umbral crítico
--             (SoC < 20% advertencia y SoC < 10% crítico) por día, con
--             justificación técnica electroquímica.
-- ----------------------------------------------------------------------------
-- Justificación técnica de negocio:
-- En celdas de LiFePO4, descargar por debajo del 20% de SoC acelera la formación
-- de micro-grietas en los electrodos y la degradación de la capa de interfase de
-- electrolito sólido (SEI). Descargas por debajo del 10% provocan riesgo de
-- inversión de polaridad y disolución de cobre, reduciendo drásticamente la vida
-- útil del banco de baterías valorado en más de $15,000 USD.
SELECT 
    l.fecha_hora::DATE AS dia,
    l.inversor_id,
    sub.nombre AS subsistema,
    COUNT(*) AS total_lecturas_dia,
    COUNT(*) FILTER (WHERE l.soc_bateria_pct <= 20) AS lecturas_soc_menor_20_advertencia,
    COUNT(*) FILTER (WHERE l.soc_bateria_pct <= 10) AS lecturas_soc_menor_10_critico,
    ROUND((COUNT(*) FILTER (WHERE l.soc_bateria_pct <= 20)::NUMERIC / COUNT(*) * 100.0), 2) AS pct_tiempo_bajo_reserva,
    MIN(l.soc_bateria_pct) AS soc_minimo_alcanzado_pct,
    ROUND(AVG(l.tension_bateria_v)::NUMERIC, 2) AS tension_bateria_promedio_v
FROM telemetria.lecturas l
JOIN microrred.inversores i ON i.id = l.inversor_id
JOIN microrred.subsistemas sub ON sub.id = i.subsistema_id
GROUP BY l.fecha_hora::DATE, l.inversor_id, sub.nombre
HAVING COUNT(*) FILTER (WHERE l.soc_bateria_pct <= 20) > 0
ORDER BY dia ASC, l.inversor_id ASC;

-- ----------------------------------------------------------------------------
-- CONSULTA 5: Días con datos incompletos y porcentaje de lecturas recibidas
--             frente a las esperadas teóricamente.
-- ----------------------------------------------------------------------------
-- En OpenCEM, la frecuencia nominal de lectura es de 1 muestra cada 13 segundos.
-- Lecturas teóricas diarias por inversor = (24 horas * 3600 segundos) / 13 s = 6.646 lecturas/día.
WITH cobertura_esperada AS (
    SELECT 
        l.fecha_hora::DATE AS dia,
        l.inversor_id,
        COUNT(*) AS lecturas_recibidas,
        6646 AS lecturas_esperadas_teoricas
    FROM telemetria.lecturas l
    GROUP BY l.fecha_hora::DATE, l.inversor_id
)
SELECT 
    dia,
    inversor_id,
    lecturas_recibidas,
    lecturas_esperadas_teoricas,
    ROUND((lecturas_recibidas::NUMERIC / lecturas_esperadas_teoricas * 100.0), 2) AS porcentaje_completitud_pct,
    (lecturas_esperadas_teoricas - lecturas_recibidas) AS lecturas_faltantes,
    CASE 
        WHEN (lecturas_recibidas::NUMERIC / lecturas_esperadas_teoricas) >= 0.95 THEN 'COMPLETO (>= 95%)'
        WHEN (lecturas_recibidas::NUMERIC / lecturas_esperadas_teoricas) >= 0.80 THEN 'PARCIALMENTE INCOMPLETO (80-94%)'
        ELSE 'CRÍTICAMENTE INCOMPLETO (< 80%)'
    END AS clasificacion_calidad
FROM cobertura_esperada
WHERE (lecturas_recibidas::NUMERIC / lecturas_esperadas_teoricas) < 0.95
ORDER BY porcentaje_completitud_pct ASC, dia ASC;

-- ----------------------------------------------------------------------------
-- CONSULTA 6: Consultas sobre registros de contexto JSON con operadores
--             nativos de PostgreSQL (->, ->>, @>, jsonb_path_query).
-- ----------------------------------------------------------------------------
-- Analiza los registros de contexto para identificar las cargas de cómputo
-- que involucran modelos de deep learning (CNNs y Transformers).
SELECT 
    c.id AS contexto_id,
    c.fecha_inicio,
    c.inversor_id,
    c.origen,
    -- Extracción con operador flecha texto (->>)
    c.payload_json->>'device' AS estacion_trabajo,
    c.payload_json->>'task_type' AS tipo_tarea,
    c.payload_json->>'command' AS comando_ejecutado,
    c.payload_json->>'directory' AS directorio_sanitizado,
    -- Verificación de contención JSONB con operador de contención (@>)
    c.payload_json @> '{"datos_personales_scrobbed": true}' AS cumple_ley_1581,
    c.descripcion_textual
FROM operacion.registros_contexto c
WHERE c.payload_json->>'task_type' LIKE '%GPU%'
   OR c.payload_json->>'command' LIKE '%deepspeed%'
   OR c.payload_json->>'command' LIKE '%train%'
ORDER BY c.fecha_inicio DESC
LIMIT 20;

-- ----------------------------------------------------------------------------
-- CONSULTA 7 (PROPUESTA): Correlación entre tareas pesadas de cómputo GPU y
--                         picos de demanda de potencia en el Inversor 1.
-- ----------------------------------------------------------------------------
-- Técnica: CTE para pre-filtrar tareas de cómputo intensivo (GPU / Deep Learning)
--          e Interval JOIN con la telemetría del Inversor 1.
WITH tareas_pesadas_gpu AS (
    SELECT 
        c.id,
        c.inversor_id,
        c.fecha_inicio,
        c.fecha_fin,
        c.payload_json->>'task_type' AS tarea_computo
    FROM operacion.registros_contexto c
    WHERE c.inversor_id = 1
      AND (c.payload_json->>'task_type' LIKE '%GPU%' OR c.payload_json->>'task_type' LIKE '%Transformer%')
    ORDER BY c.fecha_inicio DESC
    LIMIT 100
)
SELECT 
    t.id AS id_tarea_contexto,
    t.tarea_computo,
    t.fecha_inicio,
    t.fecha_fin,
    ROUND(EXTRACT(EPOCH FROM (t.fecha_fin - t.fecha_inicio)) / 60.0, 1) AS duracion_minutos,
    ROUND(AVG(l.potencia_activa_salida_w)::NUMERIC, 2) AS potencia_promedio_durante_tarea_w,
    ROUND(MAX(l.potencia_activa_salida_w)::NUMERIC, 2) AS potencia_pico_durante_tarea_w,
    ROUND(AVG(l.temperatura_inversor_1_c)::NUMERIC, 1) AS temp_promedio_inversor_c,
    COUNT(l.id) AS muestras_telemetria_asociadas
FROM tareas_pesadas_gpu t
JOIN telemetria.lecturas l ON l.inversor_id = t.inversor_id 
                          AND l.fecha_hora >= t.fecha_inicio 
                          AND l.fecha_hora <= t.fecha_fin
GROUP BY t.id, t.tarea_computo, t.fecha_inicio, t.fecha_fin
HAVING COUNT(l.id) > 10
ORDER BY potencia_pico_durante_tarea_w DESC
LIMIT 15;

-- ----------------------------------------------------------------------------
-- CONSULTA 8 (PROPUESTA): Estrés térmico y factor de carga del inversor:
--                         identificación de condiciones de riesgo para los IGBTs.
-- ----------------------------------------------------------------------------
-- Técnica: GROUP BY por rangos térmicos (CASE), agregación de potencia y horas
--          acumuladas en zonas térmicas críticas.
SELECT 
    l.inversor_id,
    CASE 
        WHEN l.temperatura_inversor_1_c < 40.0 THEN '1. Normal / Frío (< 40 °C)'
        WHEN l.temperatura_inversor_1_c BETWEEN 40.0 AND 49.9 THEN '2. Moderado (40 - 50 °C)'
        WHEN l.temperatura_inversor_1_c BETWEEN 50.0 AND 59.9 THEN '3. Elevado / Alerta (50 - 60 °C)'
        ELSE '4. Crítico / Derating (> 60 °C)'
    END AS rango_temperatura,
    COUNT(*) AS total_lecturas,
    ROUND((COUNT(*)::NUMERIC / SUM(COUNT(*)) OVER (PARTITION BY l.inversor_id) * 100.0), 2) AS pct_tiempo_operacion,
    ROUND(AVG(l.potencia_activa_salida_w)::NUMERIC, 2) AS potencia_salida_promedio_w,
    ROUND(AVG(l.porcentaje_carga_pct)::NUMERIC, 1) AS porcentaje_carga_promedio_pct,
    ROUND(MAX(l.temperatura_inversor_1_c)::NUMERIC, 1) AS temp_maxima_registrada_c
FROM telemetria.lecturas l
GROUP BY l.inversor_id, 
         CASE 
             WHEN l.temperatura_inversor_1_c < 40.0 THEN '1. Normal / Frío (< 40 °C)'
             WHEN l.temperatura_inversor_1_c BETWEEN 40.0 AND 49.9 THEN '2. Moderado (40 - 50 °C)'
             WHEN l.temperatura_inversor_1_c BETWEEN 50.0 AND 59.9 THEN '3. Elevado / Alerta (50 - 60 °C)'
             ELSE '4. Crítico / Derating (> 60 °C)'
         END
ORDER BY l.inversor_id ASC, rango_temperatura ASC;

-- ----------------------------------------------------------------------------
-- CONSULTA 9 (PROPUESTA): Estimación de ciclos de carga/descarga equivalentes
--                         y rendimiento electroquímico del banco de baterías.
-- ----------------------------------------------------------------------------
-- Técnica: Integración de energía de recarga (Ah integrados) dividida entre la
--          capacidad nominal (200 Ah) para deducir Full Equivalent Cycles (FEC).
WITH ah_bateria AS (
    SELECT 
        l.inversor_id,
        DATE_TRUNC('month', l.fecha_hora) AS mes,
        -- Corrientes negativas corresponden a recarga: abs(I_bat) * dt / 3600 = Ah recargados
        SUM(CASE WHEN l.corriente_bateria_a < 0 THEN ABS(l.corriente_bateria_a) * 13.0 / 3600.0 ELSE 0 END) AS ah_recarga,
        SUM(CASE WHEN l.corriente_bateria_a > 0 THEN l.corriente_bateria_a * 13.0 / 3600.0 ELSE 0 END) AS ah_descarga
    FROM telemetria.lecturas l
    GROUP BY l.inversor_id, DATE_TRUNC('month', l.fecha_hora)
)
SELECT 
    TO_CHAR(a.mes, 'YYYY-MM') AS mes,
    a.inversor_id,
    b.quimica,
    b.capacidad_nominal_ah,
    ROUND(a.ah_recarga::NUMERIC, 2) AS total_ah_recargados,
    ROUND(a.ah_descarga::NUMERIC, 2) AS total_ah_descargados,
    -- Ciclos completos equivalentes = Ah descargados / Capacidad nominal (200 Ah)
    ROUND((a.ah_descarga / b.capacidad_nominal_ah)::NUMERIC, 2) AS ciclos_completos_equivalentes_fec,
    -- Eficiencia coulombimétrica aproximada (Ah descarga / Ah recarga)
    ROUND((a.ah_descarga / NULLIF(a.ah_recarga, 0) * 100.0)::NUMERIC, 2) AS eficiencia_coulombica_pct
FROM ah_bateria a
JOIN microrred.bancos_bateria b ON b.inversor_id = a.inversor_id
ORDER BY mes ASC, a.inversor_id ASC;

-- ----------------------------------------------------------------------------
-- CONSULTA 10 (LÍNEA 5): Indicadores clave de rendimiento (KPI) de alarmas:
--                        Tiempo Medio de Resolución (MTTR) y frecuencia por severidad.
-- ----------------------------------------------------------------------------
-- Técnica: FILTER en agregados, funciones estadísticas de tiempo y agrupamiento por catálogo.
SELECT 
    t.codigo AS codigo_alarma,
    t.nombre AS tipo_alarma,
    a.severidad,
    COUNT(a.id) AS total_disparos,
    COUNT(*) FILTER (WHERE a.estado = 'RESUELTA') AS total_resueltas,
    COUNT(*) FILTER (WHERE a.estado = 'ACTIVA') AS total_aun_activas,
    -- MTTR en minutos
    ROUND(AVG(EXTRACT(EPOCH FROM (a.fecha_resolucion - a.fecha_deteccion)) / 60.0)::NUMERIC, 2) AS mttr_tiempo_medio_resolucion_min,
    MIN(a.fecha_deteccion) AS primer_incidente,
    MAX(a.fecha_deteccion) AS ultimo_incidente
FROM operacion.alarmas a
JOIN operacion.catalogo_tipos_alarma t ON t.id = a.tipo_alarma_id
GROUP BY t.codigo, t.nombre, a.severidad
ORDER BY total_disparos DESC;

-- ----------------------------------------------------------------------------
-- CONSULTA 11 (LÍNEA 5): Trazabilidad de Auditoría Forense (Change Data Capture)
--                        sobre modificaciones de parámetros y umbrales.
-- ----------------------------------------------------------------------------
-- Técnica: Consulta sobre JSONB de auditoría extrayendo diferencias operadas.
SELECT 
    r.id AS auditoria_id,
    r.fecha_hora,
    r.usuario_bd,
    r.rol_bd,
    r.accion,
    r.esquema_nombre || '.' || r.tabla_nombre AS entidad_modificada,
    r.registro_id,
    -- Valores antes y después en JSONB
    r.datos_anteriores,
    r.datos_nuevos,
    r.diferencias,
    r.aplicacion_cliente
FROM auditoria.registro_cambios r
WHERE r.esquema_nombre IN ('operacion', 'microrred')
ORDER BY r.fecha_hora DESC
LIMIT 20;
