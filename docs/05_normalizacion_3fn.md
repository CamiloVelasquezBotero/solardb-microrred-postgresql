# 5. Proceso de Normalización Formal hasta 3FN

## 5.1 Estado Inicial No Normalizado (Fuente Cruda OpenCEM)
En la fuente original, la información de telemetría, catálogo de equipos, configuración de protección y eventos de falla se encuentra distribuida en tablas monolíticas con claves compuestas arbitrarias y severas anomalías:

```
TABLA_ORIGINAL_SPECS (read_ts, inverter, machcode, producttype, manufacturename, sourcesn, hwver_m1, protocolver...)
TABLA_ORIGINAL_SETTINGS (read_ts, inverter, outvoltset, outfreqset, maxchgcurrset, battsoclowalarm, battfullsoc...)
TABLA_ORIGINAL_FAULT_HISTORY (read_ts, inverter, faulthistoryrecord00, faulthistoryrecord01... faulthistoryrecord31, faulthistoryrecord00_time...)
TABLA_ORIGINAL_ANALOG (read_ts, inverter, battvolt, battcurr, battsoc, battreserve, pv1power, outw_a, grid_reserve...)
```

---

## 5.2 Primera Forma Normal (1FN): Atomicidad y Eliminación de Grupos Repetitivos

### Definición y Regla
Una relación está en **1FN** si y solo si todos los dominios de sus atributos contienen exclusivamente valores atómicos e indivisibles, y no existen grupos repetitivos ni atributos multivaluados.

### Anomalías Detectadas en los Datos Reales
1. **Arreglos Numéricos Serializados como Texto Plano**:
   En la tabla `analog_measurements`, columnas como `battreserve`, `pvreserve`, `otherreserve` y `grid_reserve` almacenaban arreglos de valores tales como `"{0,0,0,0,0}"` o `"{0,0,0,0,0,0,0,0,0,0}"`.
   *Ejemplo real*:
   ```csv
   read_ts=1752472412, inverter=2, battreserve="{0,0,0,0,0}", grid_reserve="{0,0,0,0,0,0,0,0,0,0}"
   ```
2. **Grupos Repetitivos en Historial de Fallas**:
   La tabla `fault_history` definía 32 columnas de código de falla (`faulthistoryrecord00` a `faulthistoryrecord31`) y 32 columnas de tiempo de falla (`faulthistoryrecord00_time` a `faulthistoryrecord31_time`).

### Transformación Aplicada para 1FN
- Se eliminaron todas las columnas de reservas estructuradas que contenían arreglos serializados de ceros sin significado físico.
- Se descompuso el grupo repetitivo de 32 columnas de fallas en una estructura relacional independiente de eventos (`operacion.alarmas`), donde cada falla ocurrida constituye una única tupla con su propio identificador y marca de tiempo.
- Se extrajeron los arreglos de valores de configuración JSON en la tabla `operacion.registros_contexto` mediante el tipo nativo `JSONB`, donde cada clave representa un atributo atómico estructurado e indexable.

---

## 5.3 Segunda Forma Normal (2FN): Eliminación de Dependencias Parciales

### Definición y Regla
Una relación está en **2FN** si está en 1FN y ningún atributo no clave depende funcionalmente de una parte propia de una clave primaria compuesta (eliminación de dependencias funcionales parciales).

### Dependencias Parciales Detectadas en los Datos Reales
En las tablas originales `specs` y `settings`, la clave primaria era la tupla compuesta:
$$\text{PK} = (\text{read\_ts}, \text{inverter})$$
Sin embargo, se identificaron las siguientes dependencias funcionales:
1. $\text{inverter} \to \text{manufacturename, sourcesn, hwver\_m1, protocolver}$
2. $\text{inverter} \to \text{outvoltset, outfreqset, maxchgcurrset, battsoclowalarm}$

*Ejemplo tomado de los datos reales*:
En las 1,333,174 filas de la tabla `specs`, el valor del Inversor 1 siempre contenía:
```csv
inverter=1, manufacturename='INVT', sourcesn='SPI4880-202506001-A', hwver_m1=1, protocolver=1
```
Este bloque de datos estático se repetía exactamente igual en cada una de las 1.3 millones de lecturas tomadas cada 13 segundos.

### Anomalías Eliminadas
- **Anomalía de Redundancia**: Se eliminaron más de 1.3 millones de repeticiones inútiles de las cadenas `'INVT'` y los números de serie.
- **Anomalía de Modificación**: Si se actualiza el firmware del inversor 1, en la base original se debían actualizar 1,333,174 registros. En SolarDB, se actualiza una única fila en `microrred.inversores`.

### Transformación Aplicada para 2FN
Se separaron los atributos que dependen exclusivamente de `inversor` en las tablas:
- `microrred.inversores` (donde la PK es `id INT` que representa al inversor).
- `operacion.umbrales_configuracion` (donde la PK es compuesta o unívoca por `(inversor_id, tipo_alarma_id)`).
- En la tabla de telemetría resultante `telemetria.lecturas`, todos los atributos analógicos (`battvolt`, `battcurr`, `pv1power`, etc.) dependen de la totalidad de la clave compuesta:
$$(\text{inversor\_id}, \text{fecha\_hora}) \to \text{battvolt, battcurr, soc, pv1power...}$$
Ninguna variable física instantánea puede conocerse únicamente conociendo el inversor o conociendo únicamente el tiempo (porque cada inversor mide valores diferentes en el mismo segundo). Por tanto, la relación cumple estrictamente 2FN.

---

## 5.4 Tercera Forma Normal (3FN): Eliminación de Dependencias Transitivas

### Definición y Regla
Una relación está en **3FN** si está en 2FN y ningún atributo no clave depende transitivamente de la clave primaria (es decir, $X \to Y$ y $Y \to Z$ donde $Z$ es un atributo no clave).

### Dependencias Transitivas Detectadas
Al analizar los atributos del inversor y de las alarmas:
1. $\text{inversor\_id} \to \text{codigo\_modelo} \to \text{nombre\_fabricante, potencia\_nominal\_w}$
   El nombre del fabricante depende del modelo del inversor, y el modelo depende del inversor instalado.
2. $\text{inversor\_id} \to \text{subsistema\_id} \to \text{sitio\_id} \to \text{latitud, longitud, ciudad}$
   La ubicación geográfica del campus depende del sitio, y el sitio depende del subsistema.
3. $\text{alarma\_id} \to \text{tipo\_alarma\_id} \to \text{nombre\_alarma, severidad\_defecto, parametro\_evaluado}$
   La severidad por defecto y el parámetro evaluado dependen del tipo de alarma clasificado, no del ID de la instancia de la alarma en la telemetría.

### Transformación Aplicada para 3FN
Se crearon catálogos maestros independientes para romper las dependencias transitivas:
1. `microrred.fabricantes` ($\underline{\text{id}}$, nombre, pais_origen).
2. `microrred.modelos_inversor` ($\underline{\text{id}}$, fabricante_id, codigo_modelo, potencia_nominal_w).
3. `microrred.sitios` ($\underline{\text{id}}$, codigo, nombre, latitud, longitud).
4. `microrred.subsistemas` ($\underline{\text{id}}$, sitio_id, codigo, nombre).
5. `operacion.catalogo_tipos_alarma` ($\underline{\text{id}}$, codigo, nombre, severidad_defecto, parametro_evaluado).

Con esta descomposición:
- Todo atributo no clave depende **directa, completa y exclusivamente** de la clave primaria.
- Se elimina cualquier dependencia transitiva.
- El esquema resultante cumple rigurosamente con la **Tercera Forma Normal (3FN)** y la **Forma Normal de Boyce-Codd (BCNF)**.

---

## 5.5 Justificación de Decisiones de Diseño y Desnormalización Controlada

### ¿Se realizó alguna desnormalización intencional?
**No existe desnormalización en la estructura relacional de los catálogos ni en las entidades operativas**. Todas las tablas maestras de infraestructura, modelos, configuraciones y alarmas cumplen 3FN/BCNF.

En la tabla `telemetria.lecturas`, la elección del formato ancho estructurado:
1. **Cumple formalmente 3FN**: Las 24 columnas eléctricas analógicas registradas dependen funcionalmente de manera completa de la clave temporal $(\text{inversor\_id}, \text{fecha\_hora})$. No existe dependencia transitiva entre `tension_bateria_v` y `potencia_pv_w` (son magnitudes físicas independientes medidas simultáneamente por canales Modbus separados).
2. **Columna Derivada Almacenada Justificada**: En las tablas `microrred.bancos_bateria` y `microrred.arreglos_solares`, los campos `energia_nominal_kwh` y `potencia_pico_total_kwp` están definidos mediante columnas generadas determinísticas:
   ```sql
   energia_nominal_kwh NUMERIC(6,2) GENERATED ALWAYS AS (ROUND((capacidad_nominal_ah * tension_nominal_v) / 1000.0, 2)) STORED
   ```
   Esta técnica garantiza consistencia matemática perpetua a nivel de almacenamiento físico sin violar 3FN, evitando recalcular la fórmula en cada consulta analítica.
