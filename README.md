# Carer Record

Aplicación móvil para equipos de salud que permite mantener un registro continuo
de notas informales por paciente y facilitar la comunicación durante los cambios
de turno. Diseñada para funcionar en entornos con conectividad intermitente.

---

## Tecnologías principales

| Capa | Estado actual | Diseño objetivo |
| --- | --- | --- |
| App móvil | Flutter (Android) | Flutter + Drift/SQLite |
| Backend API | FastAPI (Python) | FastAPI desplegado en cloud |
| Base de datos | MariaDB en Raspberry Pi | PostgreSQL de Supabase |
| Autenticación | JWT propio | Supabase Auth |
| Archivos y audio | Disco local del servidor | Supabase Storage |
| Voz a texto | On-device y worker Python | On-device con worker opcional |
| Acceso remoto | Cloudflare Tunnel | URL HTTPS estable del backend |
| Integración | Adaptadores FHIR y HL7v2 | Gateway multihospital configurable |

La arquitectura objetivo y la estrategia de migración se documentan en
[`infra/MIGRATION_TO_SUPABASE.md`](infra/MIGRATION_TO_SUPABASE.md). Durante la
transición, el sistema continúa utilizando MariaDB y la infraestructura de la
Raspberry Pi.

---

## Estructura del repositorio

```text
carer-record/
├── app/                        # Aplicación Flutter
│   ├── lib/
│   │   ├── core/               # Configuración y tema
│   │   ├── data/
│   │   │   ├── local/          # Preferencias locales; Drift está pendiente
│   │   │   ├── remote/         # Cliente HTTP hacia el backend
│   │   │   └── services/       # Grabación y transcripción
│   │   └── presentation/       # Pantallas y widgets
│   ├── pubspec.yaml
│   └── .fvmrc                    # Flutter 3.44.9 / Dart 3.12.2
├── backend/                    # API FastAPI
│   ├── app/
│   │   ├── api/v1/routes/      # Rutas: auth, users, patients y notes
│   │   ├── core/               # Configuración, seguridad, base de datos
│   │   ├── fhir/               # Importador y mapeadores FHIR
│   │   ├── sync/               # Sincronización incremental FHIR
│   │   └── workers/            # Worker de transcripción
│   ├── requirements.txt
│   └── .python-version           # Python 3.11.11
├── integration/                # Adaptadores para sistemas hospitalarios
│   ├── adapters/
│   │   ├── fhir_adapter.py     # Importación desde FHIR R4
│   │   └── hl7v2_adapter.py    # Integración HL7v2 MLLP (en desarrollo)
│   └── README.md               # Instrucciones de integración
├── infra/                      # Infraestructura actual y plan de migración
│   ├── cloudflare/              # Configuración del túnel actual
│   ├── README.md                # Operación actual en Raspberry Pi
│   ├── MIGRATION_TO_SUPABASE.md # Plan de migración a Supabase
│   └── scripts/
│       └── setup_integration.sh
└── README.md
```

---

## Configuración del entorno de desarrollo

### Requisitos previos

- [FVM](https://fvm.app/) para instalar Flutter 3.44.9 (incluye Dart 3.12.2)
- [uv](https://docs.astral.sh/uv/) para instalar Python 3.11.11
- MariaDB ≥ 10.x
- URL de Cloudflare Tunnel del servidor actual

### 1. Clonar el repositorio

```bash
git clone https://github.com/MonarcShadow/carer-record.git
cd carer-record
```

### 2. Configurar Flutter

```bash
cd app
fvm install
fvm flutter pub get
```

FVM descarga el SDK declarado en `app/.fvmrc`. Ejecutar los comandos Flutter
siempre mediante `fvm flutter ...`, por ejemplo `fvm flutter run`.

### 3. Configurar el backend

```bash
cd backend
uv venv --python 3.11.11
uv pip install --python .venv -r requirements.txt
```

Activar el entorno cuando se necesite ejecutar comandos directamente:

```bash
# Linux, macOS y WSL
source .venv/bin/activate

# Windows PowerShell
.venv\Scripts\Activate.ps1
```

El archivo `backend/.python-version` fija el intérprete para el equipo. El
entorno virtual local (`backend/.venv`) no se versiona. `backend/requirements.txt`
contiene las dependencias de la API. Los
componentes opcionales de la infraestructura actual requieren paquetes
adicionales:

```bash
# Sincronización y adaptadores FHIR/HL7v2
pip install mysql-connector-python hl7apy

# Worker de transcripción en el servidor
pip install faster-whisper
```

Crear `backend/.env` con las variables del entorno actual:

```bash
touch .env
# Configurar DATABASE_URL y las variables del sincronizador FHIR
```

### 4. Inicializar la base de datos

Aplicar el schema en el servidor de desarrollo:

```bash
mariadb -u root -p < backend/app/core/init_db.sql
```

O usar el script de setup completo (en el servidor, sistema Linux):

```bash
bash infra/scripts/setup_integration.sh
```

### 5. Ejecutar el backend

```bash
cd backend
uvicorn app.main:app --reload --port 8000
```

La documentación de la API estará disponible en `http://localhost:8000/docs`.

### 6. Ejecutar la app Flutter

```bash
cd app
fvm flutter run
```

---

## Flujo de datos actual

```text
Teléfono (Flutter)
    │
    └── HTTPS ──▶ Cloudflare Tunnel ──▶ FastAPI ──▶ MariaDB
```

La persistencia offline con Drift/SQLite pertenece al diseño objetivo y todavía
no está implementada en la app actual.

## Flujo de datos objetivo

```text
FHIR / HL7v2 / archivos / registro manual
                    │
                    ▼
                 FastAPI
        integración + API + procesos de IA
                    │
                    ▼
        Supabase/PostgreSQL/Auth/Storage
                    ▲
                    │
           Flutter + Drift/SQLite
```

Supabase proporciona la infraestructura administrada de datos. FastAPI mantiene
la lógica de integración y negocio, y Flutter continúa siendo el frontend móvil.
Los datos importados desde hospitales serán inicialmente de solo lectura; los
eventos creados en Carer Record se almacenarán en la plataforma propia.

---

## Integración con sistemas hospitalarios

La capa de integración (`integration/`) usa el patrón Adaptador para
normalizar datos de distintos sistemas al modelo interno de la app.

Sistemas soportados actualmente:

- **FHIR R4** — importación de pacientes desde bundles JSON

En desarrollo:

- **HL7v2** — listener MLLP para mensajes ADT

Ver [`integration/README.md`](integration/README.md) para instrucciones detalladas.

---

## Convenciones del equipo

### Ramas

```text
main          ← producción / entregables estables
dev           ← integración del equipo
feature/<nombre>   ← desarrollo de funcionalidades
fix/<nombre>       ← correcciones
```

### Commits

Usar prefijos descriptivos:

```text
feat: agrega pantalla de notas de turno
fix: corrige error en sincronización offline
docs: actualiza README de integración
refactor: simplifica lógica del sync manager
```

### Pull Requests

- Toda funcionalidad nueva debe entrar por PR hacia `dev`
- Incluir descripción breve de qué hace el cambio y cómo probarlo
- Al menos un miembro del equipo debe revisar antes de mergear

---

## Equipo

Proyecto de tesis — Universidad Técnica Federico Santa María  
Equipo de cuatro integrantes.

---

## Estado del proyecto

| Fase | Descripción | Estado |
| --- | --- | --- |
| 1 | Infraestructura actual en Raspberry Pi | ✅ Completado |
| 2 | Migración a Supabase y FastAPI cloud | 📝 Diseñada |
| 3 | Autenticación y esqueleto Flutter | 🔄 En progreso |
| 4 | Funcionalidad central (notas, turnos) | 🔄 En progreso |
| 5 | Sincronización offline | ⏳ Pendiente |
| 6 | Voz a texto on-device | 🔄 En progreso |
| 7 | Integración con sistemas hospitalarios | 🔄 En progreso |

Las notas de texto y voz ya tienen implementación en Flutter y FastAPI. El flujo
de cambios de turno solo está representado en el esquema de base de datos y aún
no tiene API ni interfaz. La transcripción on-device está implementada con
Sherpa ONNX, pero queda pendiente validarla en un dispositivo objetivo.
