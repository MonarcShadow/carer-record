# Integración con sistemas hospitalarios

Este módulo implementa el patrón Adaptador para normalizar datos de distintos
sistemas clínicos al modelo interno de Carer Record.

> Esta guía describe la implementación actual conectada directamente a MariaDB.
> La arquitectura objetivo conserva los adaptadores, pero mueve la ingesta y la
> persistencia a FastAPI y Supabase. Ver el
> [`plan de migración`](../infra/MIGRATION_TO_SUPABASE.md).

---

## Arquitectura actual

```text
Sistema hospitalario (FHIR R4 / HL7v2)
        ↓
   Adaptador (integration/adapters/)
        ↓
   MariaDB — modelo interno de Carer Record
        ↓
   FastAPI → App Flutter
```

Esta es una de las rutas de integración actuales. El backend también contiene
un sincronizador y un importador FHIR en `backend/app/sync/` y
`backend/app/fhir/`. La migración consolidará estas rutas para que el resto de
la aplicación trabaje exclusivamente con el modelo interno.

---

## Sistemas soportados

### FHIR R4 (activo)

Importa pacientes desde bundles JSON generados por sistemas compatibles con FHIR R4
(Epic, Meditech, HAPI FHIR, Synthea, etc.).

**Adaptador:** `adapters/fhir_adapter.py`

### HL7v2 MLLP (en desarrollo)

Listener para mensajes ADT (admisión, traslado, alta) via protocolo MLLP.

**Adaptador:** `adapters/hl7v2_adapter.py`

---

## Datos de prueba — Synthea

Los datos de prueba se generan con [Synthea](https://github.com/synthetichealth/synthea),
un generador de pacientes sintéticos en formato FHIR R4.

### Requisitos

- Java ≥ 11

### Descargar Synthea

```bash
curl -L https://github.com/synthetichealth/synthea/releases/latest/download/synthea-with-dependencies.jar \
  -o synthea.jar
```

### Generar pacientes de prueba

```bash
java -jar synthea.jar -p 100 -s 42
```

Parámetros utilizados en el proyecto:

| Parámetro | Valor | Descripción |
| --- | --- | --- |
| `-p` | `100` | Número de pacientes a generar |
| `-s` | `42` | Semilla aleatoria — garantiza reproducibilidad |

Los bundles JSON quedan en `output/fhir/`.

> Los archivos generados (~385 MB) no se versionan en el repositorio.
> Están excluidos por `.gitignore` bajo `integration/test_data/`.

### Importar a MariaDB

```bash
pip install mysql-connector-python

python3 integration/adapters/fhir_adapter.py \
  --input integration/test_data/fhir/
```

El adaptador es idempotente: si se ejecuta más de una vez, omite los pacientes
ya importados sin generar duplicados.

---

## Configuración actual del adaptador FHIR

El adaptador heredado todavía abre una conexión directa a MariaDB mediante
`DB_CONFIG`. Durante la migración, esta dependencia será reemplazada por una
capa de ingesta de FastAPI y configuración por hospital/fuente de datos.

---

## Trabajo futuro

- Migrar la persistencia de MariaDB a PostgreSQL de Supabase.
- Configurar múltiples hospitales y fuentes de datos.
- Enviar la información normalizada a través de FastAPI.
- Completar la integración HL7v2 mediante Mirth o un gateway equivalente.
- Incorporar archivos CSV/JSON/XML y registro manual como fuentes adicionales.
