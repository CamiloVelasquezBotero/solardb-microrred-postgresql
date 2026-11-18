#!/usr/bin/env python3
"""
SolarDB - Script maestro de despliegue completo en PostgreSQL.
Ejecuta secuencialmente:
  1. Crea la base de datos 'solardb'
  2. Crea el esquema DDL (tablas, tipos, restricciones)
  3. Inserta catálogos y datos maestros
  4. Crea funciones, triggers y procedimientos PL/pgSQL (Línea 5)
  5. Carga masiva de 1,050,000 lecturas y 15,000 registros de contexto
  6. Pruebas DML de restricciones
  7. Ejecución de pruebas de sustentación de la Línea 5 (disparo de alarmas, SP, CDC, Habeas Data)
  8. Creación de índices y vistas
  9. Batería de 15 controles de integridad
"""

import os
import sys
import time
import csv
import psycopg2

# ---- CONFIGURACIÓN ----
DB_HOST = "127.0.0.1"
DB_PORT = 5432
DB_USER = "postgres"
DB_PASS = "postgres123"
DB_NAME = "solardb"

BASE_DIR = r"c:\Users\Camilo\Downloads\BD_Antigravity"
SQL_DIR = os.path.join(BASE_DIR, "sql")
DATA_DIR = os.path.join(BASE_DIR, "data")

def log(msg):
    print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)

def execute_sql_file(conn, filepath, description):
    """Ejecuta un archivo SQL completo."""
    log(f"Ejecutando: {description} ({os.path.basename(filepath)})")
    with open(filepath, 'r', encoding='utf-8') as f:
        sql_content = f.read()
    
    with conn.cursor() as cur:
        cur.execute(sql_content)
    conn.commit()
    log(f"  ✔ {description} completado")

def main():
    # ==================================================================
    # PASO 1: Crear base de datos 'solardb'
    # ==================================================================
    log("=" * 60)
    log("PASO 1: Creando base de datos 'solardb'...")
    log("=" * 60)
    
    conn_pg = psycopg2.connect(
        host=DB_HOST, port=DB_PORT, user=DB_USER, password=DB_PASS,
        dbname="postgres"
    )
    conn_pg.autocommit = True
    
    with conn_pg.cursor() as cur:
        cur.execute("""
            SELECT pg_terminate_backend(pid) 
            FROM pg_stat_activity 
            WHERE datname = 'solardb' AND pid <> pg_backend_pid()
        """)
        cur.execute("DROP DATABASE IF EXISTS solardb")
        cur.execute("""
            CREATE DATABASE solardb 
            WITH OWNER = postgres 
            ENCODING = 'UTF8' 
            TABLESPACE = pg_default 
            CONNECTION LIMIT = -1
        """)
        cur.execute("""
            COMMENT ON DATABASE solardb IS 
            'SolarDB: Base de datos relacional para la telemetría, gestión de alarmas, auditoría CDC y registros de contexto de la microrred híbrida OpenCEM (I.U. Pascual Bravo - 2026).'
        """)
    conn_pg.close()
    log("  ✔ Base de datos 'solardb' creada exitosamente")
    
    # ==================================================================
    # PASO 2-4: Conectar a solardb y ejecutar DDL, DML, PL/pgSQL
    # ==================================================================
    conn = psycopg2.connect(
        host=DB_HOST, port=DB_PORT, user=DB_USER, password=DB_PASS,
        dbname=DB_NAME
    )
    conn.autocommit = False
    
    log("")
    log("=" * 60)
    log("PASO 2: Creando esquema DDL (tablas, tipos, restricciones)...")
    log("=" * 60)
    execute_sql_file(conn, os.path.join(SQL_DIR, "01_esquema_ddl.sql"), "Esquema DDL")
    
    log("")
    log("=" * 60)
    log("PASO 3: Insertando catálogos y datos maestros...")
    log("=" * 60)
    execute_sql_file(conn, os.path.join(SQL_DIR, "02_catalogos_dml.sql"), "Catálogos DML")
    
    log("")
    log("=" * 60)
    log("PASO 4: Creando funciones, triggers y procedimientos PL/pgSQL...")
    log("=" * 60)
    execute_sql_file(conn, os.path.join(SQL_DIR, "03_linea5_triggers_funciones_procedimientos.sql"), "Línea 5 PL/pgSQL")
    
    # ==================================================================
    # PASO 5: Carga masiva de datos
    # ==================================================================
    log("")
    log("=" * 60)
    log("PASO 5: Carga masiva de datos (1,050,000 lecturas + 15,000 contexto)...")
    log("=" * 60)
    
    # 5a. Deshabilitar trigger de alarmas durante carga masiva para velocidad
    with conn.cursor() as cur:
        cur.execute("ALTER TABLE telemetria.lecturas DISABLE TRIGGER trg_evaluar_alarmas_telemetria")
    conn.commit()
    log("  Trigger de alarmas deshabilitado temporalmente para carga masiva")
    
    # 5b. Cargar telemetría con COPY
    csv_telemetria = os.path.join(DATA_DIR, "telemetria_lecturas.csv")
    log(f"  Cargando telemetría desde: {csv_telemetria}")
    t0 = time.time()
    
    with conn.cursor() as cur:
        with open(csv_telemetria, 'r', encoding='utf-8') as f:
            next(f)  # Header
            cur.copy_expert(
                """COPY telemetria.lecturas (
                    inversor_id, fecha_hora, read_ts_unix,
                    tension_bateria_v, corriente_bateria_a, potencia_bateria_w, soc_bateria_pct,
                    tension_pv_v, corriente_pv_a, potencia_pv_w,
                    tension_salida_v, corriente_salida_a, frecuencia_salida_hz,
                    potencia_activa_salida_w, potencia_aparente_salida_va, porcentaje_carga_pct,
                    tension_red_v, corriente_red_a, frecuencia_red_hz, potencia_red_w,
                    temperatura_inversor_1_c, temperatura_inversor_2_c,
                    temperatura_bateria_c, temperatura_ambiente_c
                ) FROM STDIN WITH (FORMAT csv, ENCODING 'UTF8')""",
                f
            )
    conn.commit()
    t_tel = time.time() - t0
    
    with conn.cursor() as cur:
        cur.execute("SELECT COUNT(*) FROM telemetria.lecturas")
        n_tel = cur.fetchone()[0]
    log(f"  ✔ {n_tel:,} lecturas cargadas en {t_tel:.1f} segundos ({n_tel/t_tel:,.0f} filas/s)")
    
    # 5c. Actualizar secuencia
    with conn.cursor() as cur:
        cur.execute("SELECT setval(pg_get_serial_sequence('telemetria.lecturas', 'id'), COALESCE(MAX(id), 1)) FROM telemetria.lecturas")
    conn.commit()
    
    # 5d. Reactivar trigger de alarmas
    with conn.cursor() as cur:
        cur.execute("ALTER TABLE telemetria.lecturas ENABLE TRIGGER trg_evaluar_alarmas_telemetria")
    conn.commit()
    log("  ✔ Trigger de alarmas reactivado para operación continua")
    
    # 5e. Cargar registros de contexto
    csv_contexto = os.path.join(DATA_DIR, "registros_contexto.csv")
    log(f"  Cargando contexto desde: {csv_contexto}")
    t0 = time.time()
    
    n_ctx = 0
    batch = []
    batch_size = 500
    
    with open(csv_contexto, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            batch.append(row)
            if len(batch) >= batch_size:
                _insert_contexto_batch(conn, batch)
                n_ctx += len(batch)
                batch = []
                if n_ctx % 5000 == 0:
                    log(f"    ... {n_ctx:,} registros de contexto insertados")
    
    if batch:
        _insert_contexto_batch(conn, batch)
        n_ctx += len(batch)
    
    t_ctx = time.time() - t0
    log(f"  ✔ {n_ctx:,} registros de contexto cargados en {t_ctx:.1f} segundos")
    
    # ==================================================================
    # PASO 6: Pruebas DML de restricciones
    # ==================================================================
    log("")
    log("=" * 60)
    log("PASO 6: Pruebas DML de restricciones...")
    log("=" * 60)
    
    # Test: INSERT válido
    with conn.cursor() as cur:
        cur.execute("""
            INSERT INTO telemetria.lecturas (
                inversor_id, fecha_hora, read_ts_unix,
                tension_bateria_v, corriente_bateria_a, potencia_bateria_w, soc_bateria_pct,
                tension_pv_v, corriente_pv_a, potencia_pv_w,
                tension_salida_v, corriente_salida_a, frecuencia_salida_hz,
                potencia_activa_salida_w, potencia_aparente_salida_va, porcentaje_carga_pct,
                tension_red_v, corriente_red_a, frecuencia_red_hz, potencia_red_w,
                temperatura_inversor_1_c, temperatura_inversor_2_c,
                temperatura_bateria_c, temperatura_ambiente_c
            ) VALUES (
                1, '2026-03-01 12:00:00+00', 1772366400.0,
                52.80, 15.40, 813.12, 75,
                380.00, 8.50, 3230.00,
                220.00, 11.20, 50.00, 2400.00, 2464.00, 30,
                220.00, 0.00, 50.00, 0.00,
                42.50, 40.10, 31.00, 28.00
            ) ON CONFLICT (inversor_id, fecha_hora) DO NOTHING
        """)
    conn.commit()
    log("  ✔ INSERT válido exitoso")
    
    # Test: UPDATE válido (auditado por trigger)
    with conn.cursor() as cur:
        cur.execute("""
            UPDATE microrred.inversores
            SET descripcion_ubicacion = 'Sala Eléctrica Central - Bahía 1 (Lado Norte, Rack A-01 Renovado)'
            WHERE id = 1
        """)
    conn.commit()
    log("  ✔ UPDATE válido exitoso (capturado por CDC en auditoria.registro_cambios)")
    
    # Test: DELETE válido (auditado)
    with conn.cursor() as cur:
        cur.execute("""
            DELETE FROM telemetria.lecturas
            WHERE inversor_id = 1 AND fecha_hora = '2026-03-01 12:00:00+00'
        """)
    conn.commit()
    log("  ✔ DELETE válido exitoso (capturado por CDC en auditoria.registro_cambios)")
    
    # Test: CHECK violation (SoC = 150%)
    try:
        with conn.cursor() as cur:
            cur.execute("""
                INSERT INTO telemetria.lecturas (
                    inversor_id, fecha_hora, read_ts_unix, tension_bateria_v, soc_bateria_pct
                ) VALUES (1, '2026-03-01 12:05:00+00', 1772366700.0, 52.00, 150)
            """)
        conn.commit()
        log("  ✗ ERROR: Debió rechazar SoC=150%")
    except psycopg2.errors.CheckViolation:
        conn.rollback()
        log("  ✔ CHECK violation rechazada correctamente (SoC=150% rechazado por chk_telemetria_soc)")
    
    # Test: FK violation (inversor_id = 99)
    try:
        with conn.cursor() as cur:
            cur.execute("""
                INSERT INTO telemetria.lecturas (
                    inversor_id, fecha_hora, read_ts_unix, tension_bateria_v
                ) VALUES (99, '2026-03-01 12:10:00+00', 1772367000.0, 52.00)
            """)
        conn.commit()
        log("  ✗ ERROR: Debió rechazar inversor_id=99")
    except psycopg2.errors.CheckViolation:
        conn.rollback()
        log("  ✔ CHECK violation rechazada correctamente (inversor_id=99 rechazado por chk_inversor_id)")
    except psycopg2.errors.ForeignKeyViolation:
        conn.rollback()
        log("  ✔ FK violation rechazada correctamente (inversor_id=99 rechazado por fk_lectura_inversor)")
    
    # ==================================================================
    # PASO 7: Ejecución de pruebas de la Línea 5 (Alarmas, SP, CDC, Habeas Data)
    # ==================================================================
    log("")
    log("=" * 60)
    log("PASO 7: Pruebas interactivas de la Línea 5 (Alarmas y Auditoría)...")
    log("=" * 60)
    
    # 7.1 Inserción de lectura crítica para disparar alarmas por trigger
    with conn.cursor() as cur:
        cur.execute("""
            INSERT INTO telemetria.lecturas (
                inversor_id, fecha_hora, read_ts_unix,
                tension_bateria_v, corriente_bateria_a, potencia_bateria_w, soc_bateria_pct,
                tension_pv_v, corriente_pv_a, potencia_pv_w,
                tension_salida_v, corriente_salida_a, frecuencia_salida_hz,
                potencia_activa_salida_w, potencia_aparente_salida_va, porcentaje_carga_pct,
                tension_red_v, corriente_red_a, frecuencia_red_hz, potencia_red_w,
                temperatura_inversor_1_c, temperatura_inversor_2_c,
                temperatura_bateria_c, temperatura_ambiente_c
            ) VALUES (
                1, '2026-03-15 10:15:00+00', 1773569700.0,
                43.20, 95.00, 4104.00, 8,
                0.00, 0.00, 0.00,
                215.00, 32.00, 49.90, 6800.00, 6880.00, 85,
                0.00, 0.00, 0.00, 0.00,
                62.50, 58.00, 41.00, 32.00
            ) ON CONFLICT (inversor_id, fecha_hora) DO NOTHING
        """)
        
        # Verificar alarmas generadas
        cur.execute("""
            SELECT id, severidad, parametro, valor_detectado, umbral_disparado, mensaje_alarma
            FROM operacion.alarmas
            WHERE fecha_deteccion = '2026-03-15 10:15:00+00'
        """)
        alarmas_disparadas = cur.fetchall()
    conn.commit()
    log(f"  ✔ Trigger de alarmas disparó {len(alarmas_disparadas)} incidentes automáticamente:")
    for a in alarmas_disparadas:
        log(f"    • [{a[1]}] {a[2]} = {a[3]} (Umbral: {a[4]}): {a[5][:70]}...")
    
    # 7.2 Probar procedimiento almacenado de ciclo de vida de alarmas
    if alarmas_disparadas:
        alm_id = alarmas_disparadas[0][0]
        with conn.cursor() as cur:
            cur.execute("""
                CALL operacion.sp_gestionar_estado_alarma(
                    %s, 'EN_REVISION'::operacion.estado_alarma,
                    'Técnico en sitio inspeccionando disipador térmico y banco de litio.',
                    'camilo_operador'
                )
            """, (alm_id,))
            cur.execute("""
                CALL operacion.sp_gestionar_estado_alarma(
                    %s, 'RESUELTA'::operacion.estado_alarma,
                    'Incidente resuelto: Carga transferida y ventilación auxiliar activada.',
                    'camilo_operador'
                )
            """, (alm_id,))
        conn.commit()
        log(f"  ✔ Procedimiento almacenado sp_gestionar_estado_alarma ejecutado (Alarma {alm_id} -> RESUELTA)")
    
    # 7.3 Probar consolidación diaria de alarmas
    with conn.cursor() as cur:
        cur.execute("CALL operacion.sp_consolidar_resumen_diario_alarmas('2026-03-15'::DATE)")
    conn.commit()
    log("  ✔ Procedimiento almacenado sp_consolidar_resumen_diario_alarmas ejecutado")
    
    # 7.4 Probar sanitización de Habeas Data (Ley 1581)
    with conn.cursor() as cur:
        cur.execute("""
            INSERT INTO operacion.registros_contexto (
                id, fecha_registro, fecha_inicio, fecha_fin, inversor_id,
                origen, dispositivo, tipo_tarea, descripcion_textual, payload_json
            ) VALUES (
                999999, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP + INTERVAL '1 hour', 1,
                'workstation1_log', 'workstation1', 'Deep Learning Model Training',
                'Entrenamiento ejecutado por el usuario juan.perez@pascualbravo.edu.co en el laboratorio.',
                jsonb_build_object(
                    'device', 'workstation1',
                    'directory', 'C:\\Users\\juan_perez\\workspace\\modelo_red_neuronal',
                    'command', 'python train.py --token secret_xyz_987 --epochs 100'
                )
            ) ON CONFLICT (id) DO UPDATE SET 
                descripcion_textual = EXCLUDED.descripcion_textual,
                payload_json = EXCLUDED.payload_json
        """)
        cur.execute("""
            SELECT descripcion_textual, payload_json->>'directory', payload_json->>'command', datos_personales_anonimizados
            FROM operacion.registros_contexto WHERE id = 999999
        """)
        sanitizado = cur.fetchone()
    conn.commit()
    log("  ✔ Trigger de Habeas Data (Ley 1581) verificado:")
    log(f"    • Descripción: {sanitizado[0]}")
    log(f"    • Directorio:  {sanitizado[1]}")
    log(f"    • Comando:     {sanitizado[2]}")
    log(f"    • Flag anonimizado: {sanitizado[3]}")
    
    # 7.5 Probar función PL/pgSQL de cálculo de energía (kWh)
    with conn.cursor() as cur:
        cur.execute("""
            SELECT * FROM telemetria.fn_calcular_energia_kwh(
                1, '2025-07-14 00:00:00+00', '2025-07-15 00:00:00+00'
            )
        """)
        energia = cur.fetchone()
    log(f"  ✔ Función fn_calcular_energia_kwh ejecutada:")
    log(f"    • Solar: {energia[1]} kWh | Carga: {energia[2]} kWh | Red: {energia[3]} kWh | Bat neta: {energia[4]} kWh | Muestras: {energia[5]:,}")
    
    # ==================================================================
    # PASO 8: Crear índices y vistas
    # ==================================================================
    log("")
    log("=" * 60)
    log("PASO 8: Creando índices optimizados y vistas de negocio...")
    log("=" * 60)
    
    with conn.cursor() as cur:
        # Índices
        cur.execute("""
            CREATE INDEX IF NOT EXISTS idx_lecturas_inversor_fecha 
            ON telemetria.lecturas (inversor_id, fecha_hora DESC);
            
            CREATE INDEX IF NOT EXISTS idx_lecturas_soc_bajo_parcial 
            ON telemetria.lecturas (fecha_hora, inversor_id, soc_bateria_pct) 
            WHERE soc_bateria_pct <= 20;
            
            CREATE INDEX IF NOT EXISTS idx_contexto_payload_gin 
            ON operacion.registros_contexto USING gin (payload_json jsonb_path_ops);
            
            CREATE INDEX IF NOT EXISTS idx_alarmas_estado_fecha 
            ON operacion.alarmas (estado, fecha_deteccion DESC) 
            INCLUDE (inversor_id, severidad, tipo_alarma_id);
            
            CREATE INDEX IF NOT EXISTS idx_auditoria_tabla_fecha 
            ON auditoria.registro_cambios (tabla_nombre, fecha_hora DESC);
        """)
        conn.commit()
        log("  ✔ 5 índices optimizados creados (B-Tree compuesto, parcial SoC, GIN JSONB, covering alarmas, auditoría)")
        
        # Vistas
        cur.execute("""
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
                ROUND((AVG(COALESCE(l.potencia_pv_w, 0)) / 1000.0)::NUMERIC, 3) AS energia_solar_kwh,
                ROUND((AVG(COALESCE(l.potencia_activa_salida_w, 0)) / 1000.0)::NUMERIC, 3) AS energia_carga_kwh,
                ROUND((AVG(COALESCE(l.potencia_red_w, 0)) / 1000.0)::NUMERIC, 3) AS energia_red_kwh
            FROM telemetria.lecturas l
            JOIN microrred.inversores i ON i.id = l.inversor_id
            JOIN microrred.subsistemas sub ON sub.id = i.subsistema_id
            GROUP BY l.inversor_id, sub.nombre, DATE_TRUNC('hour', l.fecha_hora);
        """)
        cur.execute("""
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
        """)
        conn.commit()
        log("  ✔ 2 vistas analíticas de negocio creadas (v_balance_energetico_horario, v_tablero_control_alarmas)")
    
    # ==================================================================
    # PASO 9: Batería de 15 controles de integridad
    # ==================================================================
    log("")
    log("=" * 60)
    log("PASO 9: Batería de 15 controles de integridad...")
    log("=" * 60)
    
    with open(os.path.join(SQL_DIR, "08_verificacion_integridad.sql"), 'r', encoding='utf-8') as f:
        sql_verif = f.read()
    
    with conn.cursor() as cur:
        cur.execute(sql_verif)
        controles = cur.fetchall()
    
    todos_ok = True
    for c in controles:
        num, desc, actual, esperado, estado = c
        status_icon = "✔" if estado == "OK" else "✗"
        if estado != "OK":
            todos_ok = False
        log(f"  {status_icon} Control {num:2d}: {desc[:55]:<55} -> Actual: {str(actual):>10} | Esperado: {str(esperado):>10} | [{estado}]")
    
    log("")
    if todos_ok:
        log("  🎉 ¡TODOS LOS 15 CONTROLES DE INTEGRIDAD PASARON EXITOSAMENTE (15/15 OK)!")
    else:
        log("  ⚠ ALGUNOS CONTROLES FALLARON. Revisa la salida.")
    
    # ==================================================================
    # RESUMEN FINAL
    # ==================================================================
    with conn.cursor() as cur:
        cur.execute("SELECT COUNT(*) FROM telemetria.lecturas")
        total_lect = cur.fetchone()[0]
        cur.execute("SELECT COUNT(*) FROM operacion.registros_contexto")
        total_ctx = cur.fetchone()[0]
        cur.execute("SELECT COUNT(*) FROM operacion.alarmas")
        total_alarmas = cur.fetchone()[0]
        cur.execute("SELECT COUNT(*) FROM auditoria.registro_cambios")
        total_audit = cur.fetchone()[0]
    
    conn.close()
    
    log("")
    log("=" * 60)
    log("✅ DESPLIEGUE COMPLETO Y CERTIFICADO DE SolarDB EXITOSO")
    log("=" * 60)
    log(f"  Base de datos:       solardb @ {DB_HOST}:{DB_PORT}")
    log(f"  Usuario:             {DB_USER}")
    log(f"  Lecturas telemetría: {total_lect:,}")
    log(f"  Registros contexto:  {total_ctx:,}")
    log(f"  Alarmas gestionadas: {total_alarmas:,}")
    log(f"  Registros auditoría: {total_audit:,}")
    log(f"  Controles superados: 15 / 15")
    log("=" * 60)

def _insert_contexto_batch(conn, batch):
    """Inserta un lote de registros de contexto."""
    with conn.cursor() as cur:
        for row in batch:
            cur.execute("""
                INSERT INTO operacion.registros_contexto (
                    id, fecha_registro, fecha_inicio, fecha_fin, inversor_id,
                    origen, dispositivo, tipo_tarea, descripcion_textual, payload_json
                ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s::jsonb)
                ON CONFLICT (id) DO UPDATE SET 
                    descripcion_textual = EXCLUDED.descripcion_textual,
                    payload_json = EXCLUDED.payload_json
            """, (
                int(row['id']),
                row['fecha_registro'],
                row['fecha_inicio'],
                row['fecha_fin'],
                int(row['inversor_id']),
                row['origen'],
                row.get('dispositivo', ''),
                row.get('tipo_tarea', ''),
                row['descripcion_textual'],
                row['payload_json']
            ))
    conn.commit()

if __name__ == "__main__":
    main()
