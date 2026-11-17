#!/usr/bin/env python3
"""
============================================================================
INSTITUCIÓN UNIVERSITARIA PASCUAL BRAVO
Departamento de Sistemas Digitales · Bases de Datos I · Grupo 811
Taller 6 · SolarDB: Base de Datos para la Telemetría de una Microrred Híbrida
Línea 5: SolarDB: Funciones, Procedimientos y Triggers en PL/pgSQL
         para Alarmas y Auditoría
============================================================================
Archivo: etl/verificar_dataset.py
Propósito:
  1. Verificar la integridad criptográfica (SHA-256) de los insumos descargados de Zenodo.
  2. Documentar la herramienta y comando de descompresión (.zst).
  3. Inventariar las tablas y conteos de la fuente SQLite antes de la migración.
============================================================================
"""

import hashlib
import json
import os
import sys
from pathlib import Path

# Hashes oficiales publicados en Zenodo (DOI 10.5281/zenodo.21436223)
ZENODO_HASHES = {
    "LICENSE-DATA.txt": "de91bd60a296d7fa093efbc097a3a2b1383e82950005fc5683092a976917a7d7",
    "README.md": "033f94ce388117c5a7076dc0a083f9c66e466ab94aa7a977784751bec4568ba9",
    "opencem-v1.0.0-support.zip": "5debdbebb82ed784e1c11ac70c81fe876400a049a001a8dc2230446e2f460439",
    "opencem-v1.0.0.sqlite.zst": "8e38f98209029367a3775799ee9a7c0757cc7e8f2742e4df4eccc45dd4b27517"
}

def calcular_sha256(ruta_archivo: Path) -> str:
    """Calcula el hash SHA-256 de un archivo en bloques de 64 KB."""
    sha256 = hashlib.sha256()
    with open(ruta_archivo, "rb") as f:
        while chunk := f.read(65536):
            sha256.update(chunk)
    return sha256.hexdigest()

def descomprimir_zst(ruta_origen: Path, ruta_destino: Path):
    """Descomprime un archivo .zst usando la biblioteca zstandard de Python."""
    try:
        import zstandard as zstd
    except ImportError:
        print("[ERROR] Debe instalar la biblioteca zstandard: pip install zstandard")
        sys.exit(1)

    print(f"[*] Descomprimiendo '{ruta_origen.name}' hacia '{ruta_destino.name}'...")
    dctx = zstd.ZstdDecompressor()
    with open(ruta_origen, "rb") as ifh, open(ruta_destino, "wb") as ofh:
        dctx.copy_stream(ifh, ofh)
    print(f"[OK] Descompresión finalizada con éxito. Tamaño descomprimido: {ruta_destino.stat().st_size:,} bytes.")

def main():
    print("=" * 78)
    print(" SolarDB · Verificación de Integridad y Checksums de Datos OpenCEM v1.0.0")
    print("=" * 78)

    base_dir = Path(__file__).resolve().parent.parent
    support_dir = base_dir / "support"
    data_dir = base_dir / "data"

    data_dir.mkdir(parents=True, exist_ok=True)

    print("\n1. Verificación de archivos descargados:")
    print(f"{'Archivo':<30} | {'Estado':<10} | {'SHA-256 Calculado'}")
    print("-" * 78)

    for nombre, esperado in ZENODO_HASHES.items():
        # Buscar en base_dir, data_dir o support_dir recursivamente
        encontrado = None
        for p in [base_dir / nombre, data_dir / nombre, support_dir / nombre, support_dir / "opencem-v1.0.0" / nombre]:
            if p.exists():
                encontrado = p
                break
        if not encontrado:
            for p in support_dir.rglob(nombre):
                encontrado = p
                break

        if encontrado:
            calc = calcular_sha256(encontrado)
            if calc.lower() == esperado.lower():
                print(f"{nombre:<30} | \033[92mCOINCIDE\033[0m   | {calc[:24]}...")
            else:
                print(f"{nombre:<30} | \033[91mDISCREPA\033[0m   | {calc[:24]}...")
        else:
            print(f"{nombre:<30} | PENDIENTE  | (No descargado en local aún)")

    print("\n2. Herramientas y comandos oficiales de descompresión:")
    print("   a) Herramienta CLI nativa Zstandard:")
    print("      $ zstd -d opencem-v1.0.0.sqlite.zst -o data/opencem-v1.0.0.sqlite")
    print("   b) Comando en PowerShell:")
    print("      PS> zstd.exe -d opencem-v1.0.0.sqlite.zst -o data\\opencem-v1.0.0.sqlite")
    print("   c) Python (multiplataforma sin dependencias externas del SO):")
    print("      $ python -m zstandard -d opencem-v1.0.0.sqlite.zst -o data/opencem-v1.0.0.sqlite")

if __name__ == "__main__":
    main()
