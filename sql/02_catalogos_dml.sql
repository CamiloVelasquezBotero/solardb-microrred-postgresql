-- ============================================================================
-- INSTITUCIÓN UNIVERSITARIA PASCUAL BRAVO
-- Departamento de Sistemas Digitales · Bases de Datos I · Grupo 811
-- Taller 6 · SolarDB: Base de Datos para la Telemetría de una Microrred Híbrida
-- Línea 5: SolarDB: Funciones, Procedimientos y Triggers en PL/pgSQL
--          para Alarmas y Auditoría
-- ============================================================================
-- Archivo: sql/02_catalogos_dml.sql
-- Propósito: Poblado de tablas maestras y catálogos de infraestructura,
--            equipos, variables físicas, tipos de alarma y umbrales base.
-- Ejecutar conectado a la base de datos "solardb" después de 01_esquema_ddl.sql.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. CATÁLOGO DE SITIOS
-- ----------------------------------------------------------------------------
INSERT INTO microrred.sitios (id, codigo, nombre, institucion, ciudad, pais, latitud, longitud, altitud_msnm, zona_horaria)
VALUES (
    1, 
    'CUHK-SZ-CAMPUS', 
    'Campus Universitario CUHK-Shenzhen (Edificio de Investigación)', 
    'The Chinese University of Hong Kong, Shenzhen', 
    'Shenzhen, Guangdong', 
    'China', 
    22.695300, 
    114.212700, 
    45.00, 
    'Asia/Shanghai'
)
ON CONFLICT (id) DO UPDATE SET 
    nombre = EXCLUDED.nombre,
    latitud = EXCLUDED.latitud,
    longitud = EXCLUDED.longitud;

-- ----------------------------------------------------------------------------
-- 2. CATÁLOGO DE FABRICANTES
-- ----------------------------------------------------------------------------
INSERT INTO microrred.fabricantes (id, nombre, pais_origen, contacto_soporte, sitio_web)
VALUES 
    (1, 'INVT Solar Technology Co., Ltd.', 'China', 'service@invt-solar.com', 'https://www.invt-solar.com'),
    (2, 'EVE Energy Co., Ltd.', 'China', 'support@evebattery.com', 'https://www.evebattery.com'),
    (3, 'LONGi Green Energy Technology Co., Ltd.', 'China', 'service@longi.com', 'https://www.longi.com')
ON CONFLICT (id) DO UPDATE SET nombre = EXCLUDED.nombre;

-- ----------------------------------------------------------------------------
-- 3. MODELOS DE INVERSORES
-- ----------------------------------------------------------------------------
INSERT INTO microrred.modelos_inversor (
    id, fabricante_id, codigo_modelo, tipo, potencia_nominal_va, potencia_nominal_w,
    tension_nominal_ac_v, frecuencia_nominal_hz, tension_bateria_dc_v, corriente_max_carga_a, corriente_max_descarga_a
)
VALUES (
    1, 
    1, 
    'SPI4880V150-500P', 
    'Inversor Híbrido Bidireccional On/Off-Grid', 
    8000.00, 
    8000.00, 
    220.00, 
    50.00, 
    51.20, 
    150.00, 
    150.00
)
ON CONFLICT (id) DO UPDATE SET codigo_modelo = EXCLUDED.codigo_modelo;

-- ----------------------------------------------------------------------------
-- 4. SUBSISTEMAS INDEPENDIENTES
-- ----------------------------------------------------------------------------
INSERT INTO microrred.subsistemas (id, sitio_id, codigo, nombre, descripcion, tipo_carga_principal, fecha_puesta_marcha, activo)
VALUES 
    (
        1, 1, 'SUB-COMP-01', 'Subsistema 1: Laboratorio de Estaciones de Cómputo (GPU/CPU)',
        'Alimenta estaciones de trabajo de alto rendimiento para entrenamiento de deep learning y compilación de software.',
        'Cómputo Científico e Inteligencia Artificial',
        '2025-07-01',
        TRUE
    ),
    (
        2, 1, 'SUB-HVAC-02', 'Subsistema 2: Climatización y Ventilación de Precisión (HVAC)',
        'Alimenta bombas de calor, manejadoras de aire y compresores de acondicionamiento térmico del campus.',
        'Climatización y Confort Térmico (HVAC)',
        '2025-07-01',
        TRUE
    )
ON CONFLICT (id) DO UPDATE SET nombre = EXCLUDED.nombre, descripcion = EXCLUDED.descripcion;

-- ----------------------------------------------------------------------------
-- 5. INVERSORES FÍSICOS INSTALADOS
-- ----------------------------------------------------------------------------
INSERT INTO microrred.inversores (
    id, subsistema_id, modelo_id, numero_serie, direccion_modbus, protocolo_version, firmware_version, descripcion_ubicacion, activo, fecha_instalacion
)
VALUES 
    (
        1, 1, 1, 'SPI4880-202506001-A', 1, 'V1.0.0', 'HW:M1-S1 FW:2.14', 
        'Sala Eléctrica Central - Bahía 1 (Lado Norte)', TRUE, '2025-07-01'
    ),
    (
        2, 2, 1, 'SPI4880-202506002-B', 2, 'V1.0.0', 'HW:M1-S1 FW:2.14', 
        'Sala Eléctrica Central - Bahía 2 (Lado Sur)', TRUE, '2025-07-01'
    )
ON CONFLICT (id) DO UPDATE SET numero_serie = EXCLUDED.numero_serie, firmware_version = EXCLUDED.firmware_version;

-- ----------------------------------------------------------------------------
-- 6. BANCOS DE BATERÍAS (LiFePO4)
-- ----------------------------------------------------------------------------
INSERT INTO microrred.bancos_bateria (
    id, inversor_id, quimica, capacidad_nominal_ah, tension_nominal_v, tension_corte_descarga_v,
    tension_flotacion_v, tension_absorcion_v, tension_maxima_proteccion_v, soc_minimo_recomendado_pct, soc_critico_pct
)
VALUES 
    (1, 1, 'LiFePO4 (Fosfato de Hierro y Litio)', 200.00, 51.20, 44.00, 54.00, 56.40, 58.40, 20, 10),
    (2, 2, 'LiFePO4 (Fosfato de Hierro y Litio)', 200.00, 51.20, 44.00, 54.00, 56.40, 58.40, 20, 10)
ON CONFLICT (inversor_id) DO UPDATE SET 
    capacidad_nominal_ah = EXCLUDED.capacidad_nominal_ah,
    soc_minimo_recomendado_pct = EXCLUDED.soc_minimo_recomendado_pct;

-- ----------------------------------------------------------------------------
-- 7. ARREGLOS SOLARES FOTOVOLTAICOS
-- ----------------------------------------------------------------------------
INSERT INTO microrred.arreglos_solares (
    id, inversor_id, numero_paneles, potencia_panel_wp, tecnologia, azimut_grados, inclinacion_grados, voc_stc_v, isc_stc_a
)
VALUES 
    (1, 1, 26, 480.00, 'Monocristalino PERC', 180.00, 22.00, 49.50, 11.80),
    (2, 2, 26, 480.00, 'Monocristalino PERC', 180.00, 22.00, 49.50, 11.80)
ON CONFLICT (inversor_id) DO UPDATE SET 
    numero_paneles = EXCLUDED.numero_paneles,
    potencia_panel_wp = EXCLUDED.potencia_panel_wp;

-- ----------------------------------------------------------------------------
-- 8. CATÁLOGO DE VARIABLES DE TELEMETRÍA FÍSICA
-- ----------------------------------------------------------------------------
INSERT INTO telemetria.variables_catalogo (
    codigo, nombre, descripcion, subsistema_componente, unidad_medida, escala_modbus, rango_min_fisico, rango_max_fisico
)
VALUES 
    ('battvolt', 'Tensión de Terminales de Batería', 'Tensión de corriente continua medida en bornes del banco de baterías.', 'BATERIA', 'V', '0.1', 40.0, 60.0),
    ('battcurr', 'Corriente Neta de Batería', 'Corriente con signo: positiva indica descarga hacia la microrred, negativa indica recarga.', 'BATERIA', 'A', '0.1', -150.0, 150.0),
    ('battsoc', 'Estado de Carga de Batería (SoC)', 'Porcentaje relativo de energía remanente en el banco electroquímico.', 'BATERIA', '%', '1.0', 0.0, 100.0),
    ('potencia_bateria_w', 'Potencia Neta de Batería', 'Potencia instantánea calculada como producto de tensión y corriente neta.', 'BATERIA', 'W', '1.0', -8000.0, 8000.0),
    ('pv1volt', 'Tensión de Entrada del Arreglo Solar MPPT 1', 'Tensión DC suministrada por las cadenas fotovoltaicas al inversor.', 'SOLAR', 'V', '0.1', 0.0, 500.0),
    ('pv1curr', 'Corriente de Entrada del Arreglo Solar MPPT 1', 'Corriente DC entregada por los paneles solares.', 'SOLAR', 'A', '0.1', 0.0, 25.0),
    ('pv1power', 'Potencia Activa Generada Solar', 'Potencia instantánea total de generación fotovoltaica.', 'SOLAR', 'W', '1.0', 0.0, 12500.0),
    ('outvolta', 'Tensión de Salida AC a la Carga (Fase A)', 'Tensión eficaz entregada a las cargas del campus.', 'CARGA', 'V', '0.1', 180.0, 250.0),
    ('outcurra', 'Corriente de Salida AC a la Carga (Fase A)', 'Corriente demandada por los equipos del subsistema.', 'CARGA', 'A', '0.1', 0.0, 45.0),
    ('outfreq', 'Frecuencia de Salida AC', 'Frecuencia eléctrica en el bus de corriente alterna de consumo.', 'CARGA', 'Hz', '0.01', 48.0, 52.0),
    ('outw_a', 'Potencia Activa Demandada por la Carga', 'Consumo de potencia real de las estaciones o equipos de climatización.', 'CARGA', 'W', '1.0', 0.0, 8000.0),
    ('outva_a', 'Potencia Aparente Demandada por la Carga', 'Potencia total combinada activa y reactiva demandada por los equipos.', 'CARGA', 'VA', '1.0', 0.0, 8000.0),
    ('loadpercenta', 'Porcentaje de Carga del Inversor', 'Factor de utilización de la capacidad nominal del inversor.', 'CARGA', '%', '1.0', 0.0, 150.0),
    ('linevolta', 'Tensión de Entrada de Red Pública (Grid)', 'Tensión eficaz proveniente de la red de distribución eléctrica externa.', 'RED', 'V', '0.1', 0.0, 260.0),
    ('linecurra', 'Corriente Tomada de la Red Pública', 'Corriente de importación desde la red eléctrica.', 'RED', 'A', '0.1', 0.0, 45.0),
    ('linefreq', 'Frecuencia de la Red Pública', 'Frecuencia de la red de suministro comercial.', 'RED', 'Hz', '0.01', 45.0, 55.0),
    ('gridpowerw_a', 'Potencia Activa Importada de la Red', 'Potencia eléctrica consumida de la red pública comercial.', 'RED', 'W', '1.0', 0.0, 8000.0),
    ('temper1', 'Temperatura Interna del Módulo Inversor 1', 'Temperatura del disipador de calor y semiconductores de potencia IGBT.', 'TERMICO', '°C', '0.1', 0.0, 100.0),
    ('temper2', 'Temperatura Interna del Módulo Inversor 2', 'Temperatura del transformador o etapa de control.', 'TERMICO', '°C', '0.1', 0.0, 100.0),
    ('temper3', 'Temperatura del Banco de Baterías', 'Sensor térmico acoplado a las celdas LiFePO4.', 'TERMICO', '°C', '0.1', 0.0, 70.0),
    ('temper4', 'Temperatura Ambiente de Sala Eléctrica', 'Temperatura ambiental de la sala de control de inversores.', 'TERMICO', '°C', '0.1', 0.0, 60.0)
ON CONFLICT (codigo) DO UPDATE SET nombre = EXCLUDED.nombre, descripcion = EXCLUDED.descripcion;

-- ----------------------------------------------------------------------------
-- 9. CATÁLOGO DE TIPOS DE ALARMA (LÍNEA DE PROFUNDIZACIÓN 5)
-- ----------------------------------------------------------------------------
INSERT INTO operacion.catalogo_tipos_alarma (
    id, codigo, nombre, severidad_defecto, parametro_evaluado, unidad_medida, descripcion, accion_recomendada
)
VALUES 
    (
        1, 'ALM-BAT-LOW-WARN', 'Advertencia de Batería Baja (SoC)', 'WARNING',
        'battsoc', '%', 'El estado de carga de la batería ha descendido por debajo del umbral de advertencia (20%).',
        'Reducir cargas no críticas o habilitar soporte de red para evitar degradación de celdas.'
    ),
    (
        2, 'ALM-BAT-LOW-CRIT', 'Alarma Crítica de Descarga Profunda de Batería', 'CRITICAL',
        'battsoc', '%', 'El estado de carga de la batería ha caído por debajo del umbral crítico (10%). Riesgo inminente de apagón.',
        'Desconectar cargas prioritarias de inmediato y activar recarga de emergencia desde red o grupo electrógeno.'
    ),
    (
        3, 'ALM-BAT-UVOLT-CRIT', 'Subtensión Crítica en Bornes de Batería', 'CRITICAL',
        'battvolt', 'V', 'Tensión de batería por debajo del límite mínimo seguro de operación (44.0 V).',
        'Inhibir descarga del inversor inmediatamente para proteger el electrolito de litio.'
    ),
    (
        4, 'ALM-BAT-OVOLT-CRIT', 'Sobretensión Peligrosa en Batería', 'CRITICAL',
        'battvolt', 'V', 'Tensión de terminales por encima del voltaje máximo de absorción (58.4 V). Riesgo de sobrepresión.',
        'Suspender inmediatamente la carga solar y de red; verificar calibración del regulador MPPT.'
    ),
    (
        5, 'ALM-BAT-OCURR-WARN', 'Sobrecorriente en Descarga de Batería', 'WARNING',
        'battcurr', 'A', 'Corriente de descarga superior al régimen nominal continuo recomendado (120 A).',
        'Verificar picos de arranque en motores o balancear cargas de computación.'
    ),
    (
        6, 'ALM-INV-TEMP-WARN', 'Temperatura Elevada en Disipador de Inversor', 'WARNING',
        'temper1', '°C', 'Temperatura de la etapa de potencia superior a 50.0 °C.',
        'Inspeccionar ventiladores forzados y rejillas de ventilación de la bahía del inversor.'
    ),
    (
        7, 'ALM-INV-TEMP-CRIT', 'Sobrecalentamiento Crítico de Inversor', 'CRITICAL',
        'temper1', '°C', 'Temperatura de semiconductores superior a 60.0 °C. Riesgo de degradación térmica de IGBTs.',
        'Reducir potencia de salida automáticamente (derating) y enviar alerta técnica urgente.'
    ),
    (
        8, 'ALM-BAT-TEMP-CRIT', 'Sobrecalentamiento en Celdas de Batería', 'CRITICAL',
        'temper3', '°C', 'Temperatura del banco de litio superior a 45.0 °C. Riesgo de embalamiento térmico.',
        'Suspender todo flujo de corriente en la batería y verificar aire acondicionado de la sala.'
    ),
    (
        9, 'ALM-INV-OVERLOAD', 'Sobrecarga de Salida del Inversor', 'WARNING',
        'loadpercenta', '%', 'Demanda de la carga supera el 95% de la capacidad nominal (8000 W).',
        'Transferir excedente de carga a la red pública o postergar tareas pesadas de cómputo/climatización.'
    ),
    (
        10, 'ALM-GRID-LOSS', 'Pérdida de Conexión a Red Eléctrica Pública (Isla)', 'INFO',
        'linevolta', 'V', 'Tensión de red cae por debajo de 50.0 V, indicando apagón de la red externa.',
        'La microrred ha entrado en modo isla autónomo; preservar energía de batería para cargas esenciales.'
    ),
    (
        11, 'ALM-GRID-ANOMALY', 'Anomalía de Tensión en Red Pública (Fluctuación)', 'WARNING',
        'linevolta', 'V', 'Tensión de red fuera de la tolerancia estándar de 220 V ± 10% (rango válido 198 V - 242 V).',
        'Proteger equipos sensibles operando desde inversor y batería hasta estabilización de la red.'
    )
ON CONFLICT (codigo) DO UPDATE SET 
    nombre = EXCLUDED.nombre,
    descripcion = EXCLUDED.descripcion,
    accion_recomendada = EXCLUDED.accion_recomendada;

-- ----------------------------------------------------------------------------
-- 10. CONFIGURACIÓN DE UMBRALES OPERATIVOS POR INVERSOR
-- ----------------------------------------------------------------------------
INSERT INTO operacion.umbrales_configuracion (
    inversor_id, tipo_alarma_id, umbral_warning, umbral_critical, activo, modificado_por
)
VALUES 
    -- Inversor 1 (Cómputo Científico)
    (1, 1, 20.00, 10.00, TRUE, 'sistema_inicializacion'),
    (1, 2, 10.00, 5.00, TRUE, 'sistema_inicializacion'),
    (1, 3, 45.00, 44.00, TRUE, 'sistema_inicializacion'),
    (1, 4, 57.50, 58.40, TRUE, 'sistema_inicializacion'),
    (1, 5, 120.00, 150.00, TRUE, 'sistema_inicializacion'),
    (1, 6, 50.00, 60.00, TRUE, 'sistema_inicializacion'),
    (1, 7, 60.00, 75.00, TRUE, 'sistema_inicializacion'),
    (1, 8, 40.00, 45.00, TRUE, 'sistema_inicializacion'),
    (1, 9, 95.00, 110.00, TRUE, 'sistema_inicializacion'),
    (1, 10, 180.00, 50.00, TRUE, 'sistema_inicializacion'),
    (1, 11, 198.00, 242.00, TRUE, 'sistema_inicializacion'),
    
    -- Inversor 2 (Climatización HVAC)
    (2, 1, 20.00, 10.00, TRUE, 'sistema_inicializacion'),
    (2, 2, 10.00, 5.00, TRUE, 'sistema_inicializacion'),
    (2, 3, 45.00, 44.00, TRUE, 'sistema_inicializacion'),
    (2, 4, 57.50, 58.40, TRUE, 'sistema_inicializacion'),
    (2, 5, 120.00, 150.00, TRUE, 'sistema_inicializacion'),
    (2, 6, 50.00, 60.00, TRUE, 'sistema_inicializacion'),
    (2, 7, 60.00, 75.00, TRUE, 'sistema_inicializacion'),
    (2, 8, 40.00, 45.00, TRUE, 'sistema_inicializacion'),
    (2, 9, 95.00, 110.00, TRUE, 'sistema_inicializacion'),
    (2, 10, 180.00, 50.00, TRUE, 'sistema_inicializacion'),
    (2, 11, 198.00, 242.00, TRUE, 'sistema_inicializacion')
ON CONFLICT (inversor_id, tipo_alarma_id) DO UPDATE SET 
    umbral_warning = EXCLUDED.umbral_warning,
    umbral_critical = EXCLUDED.umbral_critical;

-- Ajustar secuencias de claves primarias
SELECT setval(pg_get_serial_sequence('microrred.sitios', 'id'), COALESCE(MAX(id), 1)) FROM microrred.sitios;
SELECT setval(pg_get_serial_sequence('microrred.fabricantes', 'id'), COALESCE(MAX(id), 1)) FROM microrred.fabricantes;
SELECT setval(pg_get_serial_sequence('microrred.modelos_inversor', 'id'), COALESCE(MAX(id), 1)) FROM microrred.modelos_inversor;
SELECT setval(pg_get_serial_sequence('microrred.subsistemas', 'id'), COALESCE(MAX(id), 1)) FROM microrred.subsistemas;
SELECT setval(pg_get_serial_sequence('microrred.bancos_bateria', 'id'), COALESCE(MAX(id), 1)) FROM microrred.bancos_bateria;
SELECT setval(pg_get_serial_sequence('microrred.arreglos_solares', 'id'), COALESCE(MAX(id), 1)) FROM microrred.arreglos_solares;
SELECT setval(pg_get_serial_sequence('telemetria.variables_catalogo', 'id'), COALESCE(MAX(id), 1)) FROM telemetria.variables_catalogo;
SELECT setval(pg_get_serial_sequence('operacion.catalogo_tipos_alarma', 'id'), COALESCE(MAX(id), 1)) FROM operacion.catalogo_tipos_alarma;
SELECT setval(pg_get_serial_sequence('operacion.umbrales_configuracion', 'id'), COALESCE(MAX(id), 1)) FROM operacion.umbrales_configuracion;
