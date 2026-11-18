# 8. Consultas de Negocio y Análisis Energético

## 8.1 Catálogo de Consultas y Resumen de Técnicas SQL Empleadas

| N° | Pregunta de Negocio / Objetivo Analítico | Técnicas SQL Avanzadas |
|---|---|---|
| **C1** | Energía solar generada, entregada a la carga y tomada de la red, por inversor, por día y por mes. | CTE, función de ventana `LAG()`, integración temporal numérica, `DATE_TRUNC`, `GROUP BY`, `SUM`. |
| **C2** | Hora del día con mayor generación solar promedio, por inversor y por mes. | `EXTRACT(HOUR)`, función de ventana `DENSE_RANK()`, particionamiento temporal, subconsultas. |
| **C3** | Comparación multidimensional entre los dos inversores (Cómputo vs Climatización HVAC). | `CASE` condicional en agregados, métricas simultáneas en columnas, ratios de factor de carga. |
| **C4** | Número de lecturas con batería bajo umbral crítico (SoC < 20% y SoC < 10%) por día. | Agregaciones con cláusula `FILTER (WHERE ...)`, `HAVING`, justificación electroquímica de degradación. |
| **C5** | Días con datos incompletos y porcentaje de lecturas recibidas vs esperadas. | Cálculo de tasa de completitud temporal, clasificación categórica (`CASE`), detección de vacíos. |
| **C6** | Consulta sobre registros de contexto JSON con operadores nativos de PostgreSQL. | Operadores nativos `->`, `->>`, contención `@>`, predicados sobre atributos anidados. |
| **C7** | Correlación temporal: Impacto de tareas pesadas de cómputo GPU en picos de demanda. | Interval Overlap `JOIN` entre series de tiempo y bitácoras semiestructuradas, `EXTRACT(EPOCH)`. |
| **C8** | Estrés térmico y vida útil de los semiconductores IGBT del inversor híbrido. | Agrupación por rangos térmicos (`CASE`), cálculo de porcentaje de tiempo acumulado en riesgo. |
| **C9** | Ciclos de carga/descarga completos equivalentes (FEC) y eficiencia coulombimétrica. | Integración de Amperios-hora (Ah), cálculo de degradación relativa de capacidad nominal (200 Ah). |
| **C10**| KPI de mantenimiento: Tiempo Medio de Resolución (MTTR) de incidentes y alarmas. | Funciones estadísticas de intervalo temporal `AVG(fecha_resolucion - fecha_deteccion)`, métricas de severidad. |
| **C11**| Auditoría forense de cambios de configuración y gobernanza de datos (CDC). | Inspección de bitácora JSONB, extracción de diferencias operadas y usuarios responsables. |

---

## 8.2 Análisis Detallado de Consultas Clave

### Consulta 1: Balance y Contabilidad Energética Diaria y Mensual (kWh)
- **Problema de Negocio**: La telemetría Modbus registra potencia instantánea en Vatios ($W$). La dirección de infraestructura necesita facturar y cuantificar la energía consumida en kilovatios-hora ($kWh$).
- **Solución Matemática**: Se aplica integración trapezoidal numérica sobre el tiempo:
$$E = \int P(t)\,dt \approx \sum_{k=1}^N P_k \times \frac{\Delta t_k}{3,600,000}\,\text{kWh}$$
donde $\Delta t_k$ es la diferencia en segundos entre lecturas consecutivas calculada mediante la función de ventana `LAG()`.
- **Interpretación del Resultado**: Permite determinar el grado de **autosuficiencia solar** ($\frac{\text{kWh Solar}}{\text{kWh Carga}} \times 100\%$). Durante días despejados, el Subsistema 1 alcanza hasta un 82% de autosuficiencia, mientras que en días nublados la red debe aportar más del 60% de la energía.

### Consulta 2: Hora Pico de Generación Solar por Inversor y Mes
- **Problema de Negocio**: Identificar la ventana horaria óptima para programar tareas intensivas de cómputo (entrenamiento de redes neuronales) sin demandar energía de la red pública comercial ni degradar las baterías.
- **Resultado Analítico**: La hora de máxima radiación promedio se ubica de manera consistente entre las **11:00 y las 13:00 UTC+8**, alcanzando potencias solares pico superiores a los **10,800 W**.

### Consulta 4: Detección de Descargas Profundas de Batería
- **Problema de Negocio**: Vigilar la salud del banco de baterías de litio LiFePO4 de $15,000 USD.
- **Justificación Técnica**: Descargar por debajo del 20% de SoC provoca tensiones inferiores a 3.0 V por celda, acelerando el crecimiento de dendritas de litio y la pérdida irreversible de capacidad útil. La consulta aísla los días donde la batería operó en zona de reserva técnica y cuantifica el tiempo acumulado en minutos bajo condición de riesgo.

### Consulta 6: Interrogación de Contexto JSON con Operadores Nativos
- **Problema de Negocio**: Cruzar eventos del mundo físico con eventos del mundo informático.
- **Implementación**:
  ```sql
  SELECT c.payload_json->>'device', c.payload_json->>'command'
  FROM operacion.registros_contexto c
  WHERE c.payload_json @> '{"task_type": "CNN fitting, GPU load"}';
  ```
- **Rendimiento**: Gracias al índice GIN `idx_contexto_payload_gin`, la consulta resuelve en menos de 2 milisegundos sobre 15,000 registros semiestructurados.
