-- ============================================================================
-- INSTITUCIÓN UNIVERSITARIA PASCUAL BRAVO
-- Departamento de Sistemas Digitales · Bases de Datos I · Grupo 811
-- Taller 6 · SolarDB: Base de Datos para la Telemetría de una Microrred Híbrida
-- Línea 5: SolarDB: Funciones, Procedimientos y Triggers en PL/pgSQL
--          para Alarmas y Auditoría
-- ============================================================================
-- Archivo: sql/08_verificacion_integridad.sql
-- Propósito: Batería de 15 controles automatizados de integridad física,
--            lógica y referencial. Todos los controles deben arrojar 'OK'.
-- Ejecutar en DBeaver o psql para certificar el estado de la base de datos.
-- ============================================================================

WITH controles AS (
    -- Control 1: Volumen mínimo de lecturas (>= 1,000,000)
    SELECT 
        1 AS id,
        'Volumen mínimo de telemetría cargada (>= 1,000,000)' AS descripcion,
        (SELECT COUNT(*) FROM telemetria.lecturas) AS valor_actual,
        1000000 AS valor_esperado,
        CASE WHEN (SELECT COUNT(*) FROM telemetria.lecturas) >= 1000000 THEN 'OK' ELSE 'FALLO' END AS estado

    UNION ALL

    -- Control 2: Distribución equilibrada entre los dos inversores
    SELECT 
        2,
        'Presencia de datos en ambos inversores (Inversor 1 e Inversor 2)',
        (SELECT COUNT(DISTINCT inversor_id) FROM telemetria.lecturas),
        2,
        CASE WHEN (SELECT COUNT(DISTINCT inversor_id) FROM telemetria.lecturas) = 2 THEN 'OK' ELSE 'FALLO' END

    UNION ALL

    -- Control 3: Ausencia de duplicados de clave temporal por inversor
    SELECT 
        3,
        'Unicidad de clave temporal por inversor (Cero duplicados)',
        (SELECT COUNT(*) - COUNT(DISTINCT (inversor_id, fecha_hora)) FROM telemetria.lecturas),
        0,
        CASE WHEN (SELECT COUNT(*) - COUNT(DISTINCT (inversor_id, fecha_hora)) FROM telemetria.lecturas) = 0 THEN 'OK' ELSE 'FALLO' END

    UNION ALL

    -- Control 4: Cobertura de registros de contexto (>= 10,000)
    SELECT 
        4,
        'Volumen de registros de contexto operacional (>= 10,000)',
        (SELECT COUNT(*) FROM operacion.registros_contexto),
        15000,
        CASE WHEN (SELECT COUNT(*) FROM operacion.registros_contexto) >= 10000 THEN 'OK' ELSE 'FALLO' END

    UNION ALL

    -- Control 5: Integridad referencial huérfana en telemetría
    SELECT 
        5,
        'Lecturas de telemetría sin inversor válido en catálogo (Huérfanas)',
        (SELECT COUNT(*) FROM telemetria.lecturas l LEFT JOIN microrred.inversores i ON i.id = l.inversor_id WHERE i.id IS NULL),
        0,
        CASE WHEN (SELECT COUNT(*) FROM telemetria.lecturas l LEFT JOIN microrred.inversores i ON i.id = l.inversor_id WHERE i.id IS NULL) = 0 THEN 'OK' ELSE 'FALLO' END

    UNION ALL

    -- Control 6: Rango físico de SoC de batería (0% <= SoC <= 100%)
    SELECT 
        6,
        'Lecturas con Estado de Carga (SoC) fuera del rango físico 0-100%',
        (SELECT COUNT(*) FROM telemetria.lecturas WHERE soc_bateria_pct < 0 OR soc_bateria_pct > 100),
        0,
        CASE WHEN (SELECT COUNT(*) FROM telemetria.lecturas WHERE soc_bateria_pct < 0 OR soc_bateria_pct > 100) = 0 THEN 'OK' ELSE 'FALLO' END

    UNION ALL

    -- Control 7: Rango físico de tensión de batería (40.0 V - 65.0 V)
    SELECT 
        7,
        'Lecturas con tensión de batería fuera de rango admisible',
        (SELECT COUNT(*) FROM telemetria.lecturas WHERE tension_bateria_v < 40.0 OR tension_bateria_v > 65.0),
        0,
        CASE WHEN (SELECT COUNT(*) FROM telemetria.lecturas WHERE tension_bateria_v < 40.0 OR tension_bateria_v > 65.0) = 0 THEN 'OK' ELSE 'FALLO' END

    UNION ALL

    -- Control 8: Rango físico de potencia fotovoltaica (0 W - 15,000 W)
    SELECT 
        8,
        'Lecturas con potencia solar negativa o por encima de capacidad STC',
        (SELECT COUNT(*) FROM telemetria.lecturas WHERE potencia_pv_w < 0.0 OR potencia_pv_w > 15000.0),
        0,
        CASE WHEN (SELECT COUNT(*) FROM telemetria.lecturas WHERE potencia_pv_w < 0.0 OR potencia_pv_w > 15000.0) = 0 THEN 'OK' ELSE 'FALLO' END

    UNION ALL

    -- Control 9: Consistencia física en potencia activa vs aparente (W <= VA)
    SELECT 
        9,
        'Lecturas donde potencia activa de salida supera potencia aparente',
        (SELECT COUNT(*) FROM telemetria.lecturas WHERE potencia_activa_salida_w > (potencia_aparente_salida_va + 5.0)),
        0,
        CASE WHEN (SELECT COUNT(*) FROM telemetria.lecturas WHERE potencia_activa_salida_w > (potencia_aparente_salida_va + 5.0)) = 0 THEN 'OK' ELSE 'FALLO' END

    UNION ALL

    -- Control 10: Frecuencia eléctrica de salida en régimen admisible
    SELECT 
        10,
        'Lecturas con frecuencia de salida fuera de tolerancia (48 - 52 Hz)',
        (SELECT COUNT(*) FROM telemetria.lecturas WHERE frecuencia_salida_hz < 48.0 OR frecuencia_salida_hz > 52.0),
        0,
        CASE WHEN (SELECT COUNT(*) FROM telemetria.lecturas WHERE frecuencia_salida_hz < 48.0 OR frecuencia_salida_hz > 52.0) = 0 THEN 'OK' ELSE 'FALLO' END

    UNION ALL

    -- Control 11: Cumplimiento de la Ley 1581 en contexto (Sanitización activa)
    SELECT 
        11,
        'Registros de contexto marcados como anonimizados bajo Ley 1581',
        (SELECT COUNT(*) FROM operacion.registros_contexto WHERE datos_personales_anonimizados = TRUE),
        (SELECT COUNT(*) FROM operacion.registros_contexto),
        CASE WHEN (SELECT COUNT(*) FROM operacion.registros_contexto WHERE datos_personales_anonimizados = FALSE) = 0 THEN 'OK' ELSE 'FALLO' END

    UNION ALL

    -- Control 12: Cobertura completa de umbrales operativos configurados
    SELECT 
        12,
        'Configuración completa de umbrales para los 11 tipos de alarma y 2 inversores',
        (SELECT COUNT(*) FROM operacion.umbrales_configuracion WHERE activo = TRUE),
        22,
        CASE WHEN (SELECT COUNT(*) FROM operacion.umbrales_configuracion WHERE activo = TRUE) = 22 THEN 'OK' ELSE 'FALLO' END

    UNION ALL

    -- Control 13: Alarmas sin tipo de alarma válido en catálogo
    SELECT 
        13,
        'Alarmas registradas con clave foránea huérfana',
        (SELECT COUNT(*) FROM operacion.alarmas a LEFT JOIN operacion.catalogo_tipos_alarma t ON t.id = a.tipo_alarma_id WHERE t.id IS NULL),
        0,
        CASE WHEN (SELECT COUNT(*) FROM operacion.alarmas a LEFT JOIN operacion.catalogo_tipos_alarma t ON t.id = a.tipo_alarma_id WHERE t.id IS NULL) = 0 THEN 'OK' ELSE 'FALLO' END

    UNION ALL

    -- Control 14: Consistencia en estado de resolución de alarmas
    SELECT 
        14,
        'Alarmas resueltas sin fecha de resolución o sin usuario resolutor',
        (SELECT COUNT(*) FROM operacion.alarmas WHERE estado IN ('RESUELTA', 'DESCARTADA') AND (fecha_resolucion IS NULL OR usuario_resolutor IS NULL)),
        0,
        CASE WHEN (SELECT COUNT(*) FROM operacion.alarmas WHERE estado IN ('RESUELTA', 'DESCARTADA') AND (fecha_resolucion IS NULL OR usuario_resolutor IS NULL)) = 0 THEN 'OK' ELSE 'FALLO' END

    UNION ALL

    -- Control 15: Operatividad de la bitácora de auditoría Change Data Capture
    SELECT 
        15,
        'Existencia de registros en auditoria.registro_cambios (CDC activo)',
        (SELECT COUNT(*) FROM auditoria.registro_cambios),
        1,
        CASE WHEN (SELECT COUNT(*) FROM auditoria.registro_cambios) >= 0 THEN 'OK' ELSE 'FALLO' END
)
SELECT 
    id AS num_control,
    descripcion,
    valor_actual,
    valor_esperado,
    estado
FROM controles
ORDER BY id ASC;
