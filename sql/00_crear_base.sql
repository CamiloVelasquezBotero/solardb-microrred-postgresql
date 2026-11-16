-- ============================================================================
-- INSTITUCIÓN UNIVERSITARIA PASCUAL BRAVO
-- Departamento de Sistemas Digitales · Bases de Datos I · Grupo 811
-- Taller 6 · SolarDB: Base de Datos para la Telemetría de una Microrred Híbrida
-- Línea 5: SolarDB: Funciones, Procedimientos y Triggers en PL/pgSQL
--          para Alarmas y Auditoría
-- ============================================================================
-- Archivo: sql/00_crear_base.sql
-- Propósito: Creación de la base de datos "solardb" con codificación UTF-8.
-- Instrucciones:
--   1. Conectarse a PostgreSQL en la base de datos de mantenimiento ("postgres").
--   2. Ejecutar este script (NO ejecutar dentro de un bloque de transacción).
--   3. En DBeaver: Clic derecho sobre Databases > Create New Database > Nombre: solardb.
--   4. Cambiar la conexión activa a la nueva base "solardb" para continuar con 01_esquema_ddl.sql.
-- ============================================================================

-- Terminar conexiones existentes a solardb si ya existiera (para recreación limpia)
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE datname = 'solardb' AND pid <> pg_backend_pid();

-- Eliminar si existe previamente
DROP DATABASE IF EXISTS solardb;

-- Crear la base de datos con soporte completo de caracteres internacionales y UTF-8
CREATE DATABASE solardb
    WITH 
    OWNER = postgres
    ENCODING = 'UTF8'
    LC_COLLATE = 'Spanish_Colombia.1252'
    LC_CTYPE = 'Spanish_Colombia.1252'
    TABLESPACE = pg_default
    CONNECTION LIMIT = -1;

COMMENT ON DATABASE solardb IS 
'SolarDB: Base de datos relacional para la telemetría, gestión de alarmas, auditoría CDC y registros de contexto de la microrred híbrida OpenCEM (I.U. Pascual Bravo - 2026).';
