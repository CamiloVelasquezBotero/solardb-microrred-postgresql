# 9. Manejo Responsable de la Información y Cumplimiento Normativo (Ley 1581 de 2012)

## 9.1 Diagnóstico de Riesgos de Privacidad en los Registros de Contexto
El dataset OpenCEM v1.0.0 incluye una tabla de contexto operacional (`context`) que registra eventos originados en las estaciones de trabajo de cómputo del campus y anotaciones manuales del personal de mantenimiento.

La inspección forense de estos registros reveló información potencialmente sensible:
1. **Rutas Absolutas del Sistema de Archivos**: Rutas como `C:\Users\juan_perez\workspace\...` o `/home/camilo/modelos/...` que exponen directamente nombres y apellidos reales de investigadores, estudiantes y operadores de la microrred.
2. **Comandos de Consola y Argumentos Sensibles**: Parámetros de terminal que contienen nombres de repositorios privados, rutas de datos confidenciales y posibles banderas con credenciales o claves API (`--token`, `--password`).
3. **Mapeo de Hábitos y Horarios de Trabajo**: Las marcas de tiempo de inicio y fin de compilaciones o entrenamientos permiten deducir patrones de presencia física y horarios de actividad de personas específicas en los laboratorios.

---

## 9.2 Marco Normativo: Ley Estatutaria 1581 de 2012 (Habeas Data de Colombia)
En Colombia, la **Ley Estatutaria 1581 de 2012** y su Decreto Reglamentario 1377 de 2013 regulan el régimen general de protección de datos personales. Su aplicación a la base de datos **SolarDB** se fundamenta en los siguientes principios rectores:

### 1. Principio de Finalidad (Art. 4, lit. b)
- **Mandato Legal**: El tratamiento de datos debe obedecer a una finalidad legítima de acuerdo con la Constitución y la Ley, la cual debe ser informada al titular.
- **Aplicación en SolarDB**: La única finalidad legítima de la base de datos es la **optimización energética, supervisión física y modelado predictivo de la microrred**. La identidad de los investigadores o estudiantes que ejecutan tareas en las estaciones de trabajo es totalmente irrelevante para el cálculo de indicadores de potencia o energía.

### 2. Principio de Libertad y Proporcionalidad (Art. 4, lit. c y Principio de Minimización)
- **Mandato Legal**: El tratamiento solo puede ejercerse con el consentimiento previo, expreso e informado del titular. Solo deben recolectarse los datos estrictamente necesarios para cumplir la finalidad.
- **Aplicación en SolarDB**: Se aplica el principio de **Minimización de Datos** (*Data Minimization*): la microrred necesita saber qué carga computacional se ejecutó (ej. *"entrenamiento de red convolucional con 8 hilos de CPU y 1 GPU"*), pero no quién la ejecutó ni en qué carpeta privada residían los datos del usuario.

### 3. Principio de Seguridad y Confidencialidad (Art. 4, lit. g y h)
- **Mandato Legal**: La información sujeta a tratamiento debe manejarse con las medidas técnicas, humanas y administrativas necesarias para otorgar seguridad a los registros, evitando su adulteración, pérdida, consulta o uso no autorizado.
- **Aplicación en SolarDB**: Implementación de mecanismos automáticos de saneamiento a nivel de motor de base de datos antes de que la información sea persistida en disco.

---

## 9.3 Estrategia Técnica de Saneamiento y Anonimización Implementada

Para asegurar el cumplimiento estricto de la ley sin degradar el valor analítico de las bitácoras de contexto para la gestión energética, se diseñó e implementó una **estrategia de anonimización activa en el motor PostgreSQL**:

### 1. Trigger PL/pgSQL de Saneamiento Automático (`trg_sanitizar_contexto_habeas_data`)
Toda inserción o modificación en la tabla `operacion.registros_contexto` pasa obligatoriamente por la función `operacion.fn_sanitizar_contexto_habeas_data()`:
```sql
CREATE OR REPLACE FUNCTION operacion.fn_sanitizar_contexto_habeas_data()
RETURNS TRIGGER AS $$
BEGIN
    -- Ofuscar rutas de directorios personales en Windows y Linux
    IF NEW.payload_json ? 'directory' THEN
        NEW.payload_json := jsonb_set(
            NEW.payload_json, 
            '{directory}', 
            to_jsonb(regexp_replace(NEW.payload_json->>'directory', 
                     '^(/Users/[^/]+|/home/[^/]+|[A-Za-z]:\\[Uu]sers\\[^\\]+)', 
                     '[RUTA_USUARIO_OFUSCADA]'))
        );
    END IF;
    
    -- Ocultar tokens o contraseñas en comandos de consola
    IF NEW.payload_json ? 'command' THEN
        NEW.payload_json := jsonb_set(
            NEW.payload_json,
            '{command}',
            to_jsonb(regexp_replace(NEW.payload_json->>'command', 
                     '(--password|--token|--key)\s+[^\s]+', 
                     '\1 [OCULTO_LEY1581]', 'gi'))
        );
    END IF;

    -- Anonimizar correos electrónicos
    NEW.descripcion_textual := regexp_replace(
        NEW.descripcion_textual, 
        '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}', 
        '[CORREO_ANONIMIZADO]', 'g'
    );

    NEW.datos_personales_anonimizados := TRUE;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
```

### 2. Clasificación de Datos en SolarDB
| Tipo de Dato | Clasificación Legal | Tratamiento Aplicado en SolarDB |
|---|---|---|
| Mediciones de potencia, voltaje, corriente | **Datos Públicos / Técnicos** | Almacenamiento libre sin restricciones de privacidad. |
| Métricas de carga de CPU/GPU, batch size | **Datos Técnicos de Operación** | Conservados para correlación energética. |
| Nombres de usuario, identificadores de red | **Datos Privados / Semiprivados** | **Eliminados / Seudonimizados** mediante identificadores genéricos de estación (`workstation1`, `workstation2`). |
| Rutas de disco con nombres de usuario | **Datos Sensibles / Privados** | **Ofuscadas** mediante expresiones regulares en el trigger. |

---

## 9.4 Seguridad del Repositorio Git y Gestión de Secretos
En estricto cumplimiento de las directrices del taller y las buenas prácticas de seguridad de software:
1. **Cero Credenciales en Código**: Ninguna contraseña de base de datos, token de acceso, URL de conexión con credenciales embebidas ni certificados SSL forman parte del repositorio público de GitHub.
2. **Configuración de `.gitignore`**:
   Se diseñó un `.gitignore` robusto que excluye:
   - Archivos de configuración local con secretos (`*.env`, `*.conf`, `*.local.json`).
   - Archivos masivos de datos crudos (`data/*.csv`, `*.sqlite`, `*.zst`).
   - Archivos temporales de DBeaver y del sistema operativo (`.dbeaver/`, `.vscode/`, `__pycache__/`).
3. **Reproducibilidad sin Exposición**: Las instrucciones de conexión en el `README.md` utilizan variables de entorno estándar (`PGHOST`, `PGPORT`, `PGUSER`, `PGDATABASE`) y solicitan la clave interactivamente en la terminal o mediante el diálogo de conexión nativo de DBeaver.
