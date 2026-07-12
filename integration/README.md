# Integración con sistemas hospitalarios

Este módulo implementa el patrón Adaptador para normalizar datos de distintos
sistemas clínicos al modelo interno de Carer Record.

---

## Arquitectura

```
Sistema hospitalario (FHIR R4 / HL7v2)
        ↓
   Adaptador (integration/adapters/)
        ↓
   MariaDB — modelo interno de Carer Record
        ↓
   FastAPI → App Flutter
```

Los adaptadores son el único punto de contacto con sistemas externos.
El resto de la aplicación trabaja exclusivamente con el modelo interno.

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
|---|---|---|
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

## Configuración del adaptador FHIR

Las credenciales de la base de datos se configuran directamente en
`adapters/fhir_adapter.py` en la sección `DB_CONFIG`, o pueden externalizarse
a variables de entorno en fases posteriores del proyecto.

---

## Trabajo futuro

- Sincronización automática al detectar nuevos bundles FHIR
- Soporte para recursos `Encounter` y `Observation`
- Listener HL7v2 MLLP para integración en tiempo real