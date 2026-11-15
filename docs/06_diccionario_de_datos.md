# 6. Diccionario de Datos Completo y Unidades de Medida

## 6.1 Unidades de Medida Físicas y Evidencia de Deducción
Para garantizar el rigor metrológico de la base de datos, cada variable física analógica fue contrastada contra:
1. El archivo oficial `documentation/column_dictionary.json` y `column_dictionary.csv` del dataset OpenCEM v1.0.0.
2. El artículo científico de los autores en arXiv:2604.05429 (*"OpenCEM: Multimodal photovoltaic and battery microgrid dataset with context records and sky imagery"*).
3. El protocolo de registros industriales Modbus RTU del inversor híbrido SPI4880V150-500P.

| Variable Física | Columna en SolarDB | Unidad | Rango Típico | Evidencia de Deducción Documental |
|---|---|:---:|:---:|---|
| **Tensión de Batería** | `tension_bateria_v` | **V** (Voltios) | 44.0 a 58.4 V | `column_dictionary.json`: `unit: "V"`, `description: "Battery terminal voltage"`. Batería LiFePO4 de 16 celdas en serie (3.2V nominal $\times$ 16 = 51.2V). |
| **Corriente Neta Batería** | `corriente_bateria_a` | **A** (Amperios) | -150.0 a 150.0 A | `column_dictionary.json`: `unit: "A"`, `description: "Signed battery current; positive denotes discharge and negative denotes charge"`. |
| **Estado de Carga Batería** | `soc_bateria_pct` | **%** (Porcentaje) | 0 a 100 % | `column_dictionary.json`: `unit: "%"`, `description: "Processed battsoc field in instantaneous measurements"`. |
| **Tensión Solar Fotovoltaica** | `tension_pv_v` | **V** (Voltios) | 0.0 a 500.0 V | `column_dictionary.json`: `unit: "V"`, `description: "PV input-channel 1 voltage"`. Arreglo de 26 paneles con Voc en circuito abierto ~49.5V. |
| **Corriente Solar Fotovoltaica** | `corriente_pv_a` | **A** (Amperios) | 0.0 a 25.0 A | `column_dictionary.json`: `unit: "A"`, `description: "PV input-channel 1 current"`. |
| **Potencia Solar Activa** | `potencia_pv_w` | **W** (Vatios) | 0 a 12,500 W | `column_dictionary.json`: `unit: "W"`, `description: "PV input-channel 1 active power"`. Corresponde a la capacidad nominal pico del arreglo (12.48 kWp). |
| **Tensión AC de Salida** | `tension_salida_v` | **V** (Voltios) | 215.0 a 225.0 V | `column_dictionary.json`: `unit: "V"`, `description: "Processed outvolta field"`. Suministro monofásico nominal de 220 VAC. |
| **Frecuencia AC de Salida** | `frecuencia_salida_hz` | **Hz** (Hercio) | 49.5 a 50.5 Hz | `column_dictionary.json`: `unit: "Hz"`, `description: "Processed outfreq field"`. Frecuencia de la red de China (50 Hz). |
| **Potencia Activa de Salida** | `potencia_activa_salida_w` | **W** (Vatios) | 0 a 8,000 W | `column_dictionary.json`: `unit: "W"`, `description: "Processed outw_a field"`. Capacidad nominal del inversor híbrido SPI4880 (8 kW). |
| **Potencia Aparente Salida** | `potencia_aparente_salida_va`| **VA** (Volt-Amp) | 0 a 8,000 VA | `column_dictionary.json`: `unit: "VA"`, `description: "Processed outva_a field"`. |
| **Factor de Carga Inversor** | `porcentaje_carga_pct` | **%** (Porcentaje) | 0 a 150 % | `column_dictionary.json`: `unit: "%"`, `description: "Processed loadpercenta field"`. Ratio de carga respecto a los 8 kW nominales. |
| **Tensión de Red Pública** | `tension_red_v` | **V** (Voltios) | 0.0 a 240.0 V | `column_dictionary.json`: `unit: "V"`, `description: "Processed linevolta field"`. Suministro comercial 220 VAC. Cae a 0 V en isla. |
| **Potencia Importada de Red** | `potencia_red_w` | **W** (Vatios) | 0 a 8,000 W | `column_dictionary.json`: `unit: "W"`, `description: "Processed gridpowerw_a field"`. Potencia activa tomada de la acometida. |
| **Temperatura Disipador 1** | `temperatura_inversor_1_c` | **°C** (Celsius) | 20.0 a 75.0 °C | `column_dictionary.json`: `unit: "degrees C"`, `description: "Processed temper1 field"`. Sensor en disipador térmico de IGBTs. |
| **Temperatura Batería** | `temperatura_bateria_c` | **°C** (Celsius) | 15.0 a 45.0 °C | `column_dictionary.json`: `unit: "degrees C"`, `description: "Processed temper3 field"`. Sensor acoplado a celdas LiFePO4. |

---

## 6.2 Especificación Detallada por Tabla

### Tabla: `microrred.sitios`
- **Descripción**: Sedes o campus físicos universitarios donde se encuentran desplegadas las microrredes.
- **Columnas**:
  * `id` (SERIAL, PK): Identificador único autoincremental del sitio.
  * `codigo` (VARCHAR(20), NOT NULL, UNIQUE): Código corto alfanumérico (ej. `'CUHK-SZ-CAMPUS'`).
  * `nombre` (VARCHAR(100), NOT NULL): Nombre descriptivo del campus y edificio.
  * `institucion` (VARCHAR(150), NOT NULL, DEFAULT `'CUHK-Shenzhen'`): Entidad académica operadora.
  * `ciudad` (VARCHAR(100), NOT NULL): Ciudad de ubicación física.
  * `pais` (VARCHAR(50), NOT NULL, DEFAULT `'China'`): País.
  * `latitud` (NUMERIC(9,6), NOT NULL, CHECK latitud BETWEEN -90 AND 90): Coordenada geográfica de latitud.
  * `longitud` (NUMERIC(9,6), NOT NULL, CHECK longitud BETWEEN -180 AND 180): Coordenada geográfica de longitud.
  * `altitud_msnm` (NUMERIC(6,2), NULL): Elevación sobre el nivel del mar en metros.
  * `zona_horaria` (VARCHAR(50), NOT NULL, DEFAULT `'Asia/Shanghai'`): Huso horario IANA oficial.
  * `fecha_creacion` (TIMESTAMPTZ, NOT NULL, DEFAULT CURRENT_TIMESTAMP): Marca de tiempo de registro.

### Tabla: `microrred.fabricantes`
- **Descripción**: Proveedores y fabricantes de los equipos industriales de conversión y almacenamiento.
- **Columnas**:
  * `id` (SERIAL, PK): Identificador único del fabricante.
  * `nombre` (VARCHAR(100), NOT NULL, UNIQUE): Nombre comercial corporativo.
  * `pais_origen` (VARCHAR(50), NULL): País de origen de la casa matriz.
  * `contacto_soporte` (VARCHAR(150), NULL): Correo electrónico de asistencia técnica.
  * `sitio_web` (VARCHAR(255), NULL): URL del portal corporativo.

### Tabla: `microrred.modelos_inversor`
- **Descripción**: Catálogo técnico y ficha de homologación de modelos de inversores híbridos.
- **Columnas**:
  * `id` (SERIAL, PK): Identificador único del modelo.
  * `fabricante_id` (INT, NOT NULL, FK `fabricantes.id` ON DELETE RESTRICT ON UPDATE CASCADE): Fabricante responsable.
  * `codigo_modelo` (VARCHAR(50), NOT NULL, UNIQUE): Referencia industrial (ej. `'SPI4880V150-500P'`).
  * `tipo` (VARCHAR(50), NOT NULL): Tipo topológico de inversor.
  * `potencia_nominal_va` (NUMERIC(10,2), NOT NULL, DEFAULT 8000.00): Potencia aparente nominal en VA.
  * `potencia_nominal_w` (NUMERIC(10,2), NOT NULL, DEFAULT 8000.00, CHECK > 0): Potencia activa continua nominal en Vatios.
  * `tension_nominal_ac_v` (NUMERIC(6,2), NOT NULL, DEFAULT 220.00): Tensión AC nominal de salida.
  * `frecuencia_nominal_hz` (NUMERIC(4,2), NOT NULL, DEFAULT 50.00): Frecuencia nominal en Hertz.
  * `tension_bateria_dc_v` (NUMERIC(5,2), NOT NULL, DEFAULT 51.20): Tensión nominal del bus DC de baterías.
  * `corriente_max_carga_a` (NUMERIC(6,2), NOT NULL, DEFAULT 150.00): Corriente máxima admisible de carga.
  * `corriente_max_descarga_a` (NUMERIC(6,2), NOT NULL, DEFAULT 150.00): Corriente máxima de descarga.

### Tabla: `microrred.subsistemas`
- **Descripción**: Unidades funcionales independientes en las que se divide operativamente la microrred.
- **Columnas**:
  * `id` (SERIAL, PK): Identificador único del subsistema.
  * `sitio_id` (INT, NOT NULL, FK `sitios.id` ON DELETE RESTRICT ON UPDATE CASCADE): Campus sede.
  * `codigo` (VARCHAR(20), NOT NULL, UNIQUE): Identificador corto (`'SUB-COMP-01'`, `'SUB-HVAC-02'`).
  * `nombre` (VARCHAR(100), NOT NULL): Denominación del subsistema.
  * `descripcion` (TEXT, NULL): Descripción del alcance funcional y cargas atendidas.
  * `tipo_carga_principal` (VARCHAR(100), NOT NULL): Naturaleza del consumo atendido.
  * `fecha_puesta_marcha` (DATE, NOT NULL): Fecha de inicio de operaciones.
  * `activo` (BOOLEAN, NOT NULL, DEFAULT TRUE): Estado operativo.

### Tabla: `microrred.inversores`
- **Descripción**: Instancias físicas de inversores híbridos leídos periódicamente por telemetría Modbus.
- **Columnas**:
  * `id` (INT, PK, CHECK id IN (1, 2)): Identificador lógico del inversor en el dataset (1 y 2).
  * `subsistema_id` (INT, NOT NULL, UNIQUE, FK `subsistemas.id` ON DELETE RESTRICT ON UPDATE CASCADE): Subsistema asignado.
  * `modelo_id` (INT, NOT NULL, FK `modelos_inversor.id` ON DELETE RESTRICT ON UPDATE CASCADE): Modelo de equipo.
  * `numero_serie` (VARCHAR(100), NOT NULL, UNIQUE): Número de serie único de placa de fábrica.
  * `direccion_modbus` (INT, NOT NULL, DEFAULT 1, CHECK > 0): ID de esclavo en bus RS485.
  * `protocolo_version` (VARCHAR(20), NOT NULL): Versión de mapa de registros Modbus.
  * `firmware_version` (VARCHAR(50), NOT NULL): Versión compilada del firmware del microcontrolador.
  * `descripcion_ubicacion` (VARCHAR(150), NULL): Sala y rack de montaje.
  * `activo` (BOOLEAN, NOT NULL, DEFAULT TRUE): Estado operativo del equipo.
  * `fecha_instalacion` (DATE, NOT NULL): Fecha de montaje físico.

### Tabla: `telemetria.lecturas`
- **Descripción**: Series de tiempo de lecturas analógicas instantáneas registradas en formato ancho optimizado.
- **Columnas**:
  * `id` (BIGSERIAL, PK): Identificador único secuencial de la lectura.
  * `inversor_id` (INT, NOT NULL, FK `inversores.id` ON DELETE RESTRICT ON UPDATE CASCADE): Inversor emisor.
  * `fecha_hora` (TIMESTAMPTZ, NOT NULL): Marca temporal estándar con zona horaria UTC.
  * `read_ts_unix` (NUMERIC(16,6), NOT NULL): Marca temporal original en segundos Unix.
  * `tension_bateria_v` (NUMERIC(6,2), CHECK 0..80 V): Tensión en bornes de batería en Voltios.
  * `corriente_bateria_a` (NUMERIC(7,2)): Corriente con signo (+ descarga, - carga) en Amperios.
  * `potencia_bateria_w` (NUMERIC(9,2)): Potencia neta de batería en Vatios ($V_{bat} \times I_{bat}$).
  * `soc_bateria_pct` (INT, CHECK 0..100 %): Porcentaje de estado de carga remanente.
  * `tension_pv_v` (NUMERIC(6,2), CHECK 0..600 V): Tensión de paneles fotovoltaicos.
  * `corriente_pv_a` (NUMERIC(6,2)): Corriente entregada por el arreglo solar.
  * `potencia_pv_w` (NUMERIC(8,2), CHECK 0..20000 W): Potencia de generación solar activa en Vatios.
  * `tension_salida_v` (NUMERIC(6,2)): Tensión eficaz AC suministrada a las cargas.
  * `corriente_salida_a` (NUMERIC(6,2)): Corriente AC demandada por las cargas.
  * `frecuencia_salida_hz` (NUMERIC(5,2), CHECK 0..70 Hz): Frecuencia de salida en Hertz.
  * `potencia_activa_salida_w` (NUMERIC(8,2)): Potencia real demandada por las cargas en Vatios.
  * `potencia_aparente_salida_va` (NUMERIC(8,2)): Potencia aparente total en Volt-Amperios.
  * `porcentaje_carga_pct` (INT, CHECK 0..300 %): Factor de utilización del inversor.
  * `tension_red_v` (NUMERIC(6,2)): Tensión de red pública comercial (0 V en isla).
  * `corriente_red_a` (NUMERIC(6,2)): Corriente tomada de la red eléctrica.
  * `frecuencia_red_hz` (NUMERIC(5,2), CHECK 0..70 Hz): Frecuencia de la red pública.
  * `potencia_red_w` (NUMERIC(8,2)): Potencia activa importada de la red en Vatios.
  * `temperatura_inversor_1_c` (NUMERIC(5,2), CHECK -20..150 °C): Temperatura en disipador de IGBTs.
  * `temperatura_inversor_2_c` (NUMERIC(5,2), CHECK -20..150 °C): Temperatura en transformador/control.
  * `temperatura_bateria_c` (NUMERIC(5,2)): Temperatura de celdas electroquímicas.
  * `temperatura_ambiente_c` (NUMERIC(5,2)): Temperatura ambiente en la sala eléctrica.
  * `es_imputado` (BOOLEAN, NOT NULL, DEFAULT FALSE): Bandera de dato interpolado o medido.
  * `fecha_insercion` (TIMESTAMPTZ, NOT NULL, DEFAULT CURRENT_TIMESTAMP): Timestamp de auditoría de carga.
  - **Restricción de Unicidad**: `UNIQUE (inversor_id, fecha_hora)`.

### Tabla: `operacion.registros_contexto`
- **Descripción**: Bitácora de contexto operacional y cargas de cómputo en formato JSONB.
- **Columnas**:
  * `id` (BIGINT, PK): Identificador único del registro de contexto.
  * `fecha_registro` (TIMESTAMPTZ, NOT NULL): Momento en que se registró la bitácora.
  * `fecha_inicio` (TIMESTAMPTZ, NOT NULL): Inicio del intervalo de aplicabilidad del contexto.
  * `fecha_fin` (TIMESTAMPTZ, NOT NULL, CHECK fecha_fin >= fecha_inicio): Fin del intervalo.
  * `inversor_id` (INT, NOT NULL, FK `inversores.id` ON DELETE RESTRICT ON UPDATE CASCADE): Inversor asociado.
  * `origen` (VARCHAR(100), NOT NULL): Fuente emisora (ej. `'workstation1_log'`).
  * `dispositivo` (VARCHAR(100), NULL): Identificador de la máquina cliente o estación.
  * `tipo_tarea` (VARCHAR(150), NULL): Categoría de carga (ej. `'CNN fitting, GPU load'`).
  * `descripcion_textual` (TEXT, NOT NULL): Explicación legible del evento.
  * `payload_json` (JSONB, NOT NULL): Estructura semiestructurada completa de metadatos.
  * `datos_personales_anonimizados` (BOOLEAN, NOT NULL, DEFAULT FALSE): Bandera de validación Ley 1581.
  * `fecha_insercion` (TIMESTAMPTZ, NOT NULL, DEFAULT CURRENT_TIMESTAMP): Timestamp de persistencia.

### Tabla: `operacion.catalogo_tipos_alarma`
- **Descripción**: Catálogo normalizado de incidentes operacionales, severidad y acciones recomendadas.
- **Columnas**:
  * `id` (SERIAL, PK): Identificador del tipo de alarma.
  * `codigo` (VARCHAR(30), NOT NULL, UNIQUE): Código mnemotécnico (ej. `'ALM-BAT-LOW-CRIT'`).
  * `nombre` (VARCHAR(100), NOT NULL): Nombre descriptivo de la contingencia.
  * `severidad_defecto` (operacion.nivel_severidad, NOT NULL, DEFAULT `'WARNING'`): Severidad base.
  * `parametro_evaluado` (VARCHAR(50), NOT NULL): Variable de telemetría monitoreada.
  * `unidad_medida` (VARCHAR(20), NOT NULL): Unidad física de la magnitud evaluada.
  * `descripcion` (TEXT, NOT NULL): Detalle del fenómeno físico causante.
  * `accion_recomendada` (TEXT, NULL): Procedimiento operativo estándar (SOP) ante el disparo.

### Tabla: `operacion.umbrales_configuracion`
- **Descripción**: Parámetros de disparo ajustables individualmente por inversor.
- **Columnas**:
  * `id` (SERIAL, PK): Identificador del umbral configurado.
  * `inversor_id` (INT, NOT NULL, FK `inversores.id` ON DELETE RESTRICT ON UPDATE CASCADE): Inversor objetivo.
  * `tipo_alarma_id` (INT, NOT NULL, FK `catalogo_tipos_alarma.id` ON DELETE RESTRICT ON UPDATE CASCADE): Tipo de alarma.
  * `umbral_warning` (NUMERIC(10,2), NOT NULL): Límite de advertencia.
  * `umbral_critical` (NUMERIC(10,2), NOT NULL): Límite crítico de actuación inmediata.
  * `activo` (BOOLEAN, NOT NULL, DEFAULT TRUE): Bandera de activación del detector.
  * `fecha_modificacion` (TIMESTAMPTZ, NOT NULL, DEFAULT CURRENT_TIMESTAMP): Fecha de último ajuste.
  * `modificado_por` (VARCHAR(100), NOT NULL, DEFAULT CURRENT_USER): Usuario responsable del cambio.
  - **Restricción de Unicidad**: `UNIQUE (inversor_id, tipo_alarma_id)`.

### Tabla: `operacion.alarmas`
- **Descripción**: Bitácora de incidentes y alarmas disparadas automáticamente por triggers PL/pgSQL.
- **Columnas**:
  * `id` (BIGSERIAL, PK): Identificador único del evento de alarma.
  * `inversor_id` (INT, NOT NULL, FK `inversores.id` ON DELETE RESTRICT ON UPDATE CASCADE): Inversor afectado.
  * `tipo_alarma_id` (INT, NOT NULL, FK `catalogo_tipos_alarma.id` ON DELETE RESTRICT ON UPDATE CASCADE): Categoría.
  * `fecha_deteccion` (TIMESTAMPTZ, NOT NULL): Momento exacto del disparo.
  * `lectura_id` (BIGINT, NULL, FK `telemetria.lecturas.id` ON DELETE SET NULL ON UPDATE CASCADE): Lectura causante.
  * `severidad` (operacion.nivel_severidad, NOT NULL): Severidad asignada (`'INFO'`, `'WARNING'`, `'CRITICAL'`).
  * `parametro` (VARCHAR(50), NOT NULL): Nombre de la variable física evaluada.
  * `valor_detectado` (NUMERIC(10,2), NOT NULL): Magnitud física medida durante el evento.
  * `umbral_disparado` (NUMERIC(10,2), NOT NULL): Valor del límite superado.
  * `mensaje_alarma` (TEXT, NOT NULL): Descripción circunstanciada generada por el trigger.
  * `estado` (operacion.estado_alarma, NOT NULL, DEFAULT `'ACTIVA'`): Estado (`'ACTIVA'`, `'EN_REVISION'`, `'RESUELTA'`, `'DESCARTADA'`).
  * `fecha_resolucion` (TIMESTAMPTZ, NULL): Momento de cierre del incidente.
  * `usuario_resolutor` (VARCHAR(100), NULL): Operador que cerró la alarma.
  * `comentario_resolucion` (TEXT, NULL): Informe técnico de solución.
  * `fecha_creacion` (TIMESTAMPTZ, NOT NULL, DEFAULT CURRENT_TIMESTAMP): Timestamp de registro.
  - **Restricción CHECK**: Consistencia de resolución (`chk_resolucion_consistente`).

### Tabla: `auditoria.registro_cambios`
- **Descripción**: Bitácora inmutable de Change Data Capture (CDC) para auditoría forense y cumplimiento.
- **Columnas**:
  * `id` (BIGSERIAL, PK): Identificador único secuencial del evento auditado.
  * `fecha_hora` (TIMESTAMPTZ, NOT NULL, DEFAULT CURRENT_TIMESTAMP): Momento exacto de la operación DML.
  * `usuario_bd` (VARCHAR(100), NOT NULL, DEFAULT CURRENT_USER): Rol activo de PostgreSQL que ejecutó el comando.
  * `rol_bd` (VARCHAR(100), NOT NULL, DEFAULT SESSION_USER): Rol de sesión autenticado.
  * `accion` (auditoria.accion_auditoria, NOT NULL): Operación ejecutada (`'INSERT'`, `'UPDATE'`, `'DELETE'`).
  * `esquema_nombre` (VARCHAR(50), NOT NULL): Esquema de la tabla afectada.
  * `tabla_nombre` (VARCHAR(50), NOT NULL): Nombre de la tabla afectada.
  * `registro_id` (VARCHAR(100), NULL): Clave primaria de la fila modificada.
  * `datos_anteriores` (JSONB, NULL): Imagen previa de la tupla (`OLD` serializado a JSONB).
  * `datos_nuevos` (JSONB, NULL): Imagen posterior de la tupla (`NEW` serializado a JSONB).
  * `diferencias` (JSONB, NULL): Mapa diferencial de columnas alteradas (`clave: {antes, despues}`).
  * `ip_cliente` (INET, NULL): Dirección IP del cliente conectado (`inet_client_addr()`).
  * `aplicacion_cliente` (VARCHAR(150), NULL): Nombre del software emisor (ej. `'DBeaver 24.0.0'`).
