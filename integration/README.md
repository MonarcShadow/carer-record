# Carer Record

Aplicación móvil para equipos de salud que permite mantener un registro continuo
de notas informales por paciente y facilitar la comunicación durante los cambios
de turno. Diseñada para funcionar en entornos con conectividad intermitente.

---

## Tecnologías principales

| Capa | Tecnología |
|---|---|
| App móvil | Flutter (Android) |
| Backend API | FastAPI (Python) |
| Base de datos | MariaDB |
| Almacenamiento local | Drift + SQLite |
| Voz a texto | On-device (sin conexión) |
| Acceso remoto al servidor | Cloudflare Tunnel (Named Tunnel) |
| Control de versiones | GitHub |

---

## Estructura del repositorio

```
carer-record/
├── app/                        # Aplicación Flutter
│   ├── lib/
│   │   ├── core/               # Constantes, errores, tema, utilidades
│   │   ├── data/
│   │   │   ├── local/          # Base de datos local (Drift + SQLite)
│   │   │   ├── remote/         # Cliente HTTP hacia el backend
│   │   │   └── sync/           # Lógica offline-first / sincronización
│   │   ├── domain/             # Modelos, repositorios, casos de uso
│   │   └── presentation/       # Pantallas y widgets
│   └── pubspec.yaml
├── backend/                    # API FastAPI
│   ├── app/
│   │   ├── api/v1/routes/      # Rutas: auth, patients, notes, sync
│   │   ├── core/               # Configuración, seguridad, base de datos
│   │   ├── models/             # Modelos ORM (SQLAlchemy)
│   │   ├── schemas/            # DTOs Pydantic
│   │   └── services/           # Lógica de negocio
│   ├── requirements.txt
│   └── systemd/                # Servicio del sistema para producción
├── ai/                         # Módulo de voz a texto (on-device)
│   └── voice_to_text/
├── integration/                # Adaptadores para sistemas hospitalarios
│   ├── adapters/
│   │   ├── fhir_adapter.py     # Importación desde FHIR R4
│   │   └── hl7v2_adapter.py    # Integración HL7v2 MLLP (en desarrollo)
│   └── README.md               # Instrucciones de integración
├── infra/                      # Infraestructura y scripts
│   ├── scripts/
│   │   └── setup_integration.sh
│   ├── cloudflare/
│   │   └── config.yml.example  # Plantilla de configuración del túnel (sin credenciales)
│   └── README.md               # Guía de configuración del servidor y túnel
└── docs/                       # Documentación del proyecto
    ├── architecture.md
    ├── adr/                    # Architecture Decision Records
    └── thesis/                 # Archivos LaTeX del informe
```

---

## Configuración del entorno de desarrollo

### Requisitos previos

- [Flutter SDK](https://docs.flutter.dev/get-started/install) ≥ 3.x
- Python ≥ 3.11
- MariaDB ≥ 10.x
- URL del túnel de desarrollo (coordinar con el equipo — ver [`infra/README.md`](infra/README.md))

### 1. Clonar el repositorio

```bash
git clone https://github.com/<org>/carer-record.git
cd carer-record
```

### 2. Configurar el backend

```bash
cd backend
python -m venv venv
source venv/bin/activate

pip install -r requirements.txt
```

Crear el archivo de variables de entorno:

```bash
cp .env.example .env
# Editar .env con las credenciales del servidor de desarrollo
```

### 3. Inicializar la base de datos

Aplicar el schema en el servidor de desarrollo:

```bash
mariadb -u root -p < backend/app/core/init_db.sql
```

O usar el script de setup completo (en el servidor, sistema Linux):

```bash
bash infra/scripts/setup_integration.sh
```

### 4. Ejecutar el backend

```bash
cd backend
uvicorn app.main:app --reload --port 8000
```

La documentación de la API estará disponible en `http://localhost:8000/docs`.

### 5. Configurar la app Flutter

```bash
cd app
flutter pub get
flutter run
```

---

## Flujo de datos

```
Teléfono (Flutter)
    │
    ├── Con conexión  ──▶  Cloudflare Tunnel  ──▶  FastAPI  ──▶  MariaDB (servidor)
    │
    └── Sin conexión  ──▶  SQLite local (Drift)
                               │
                               └── Sync al reconectar ──▶ FastAPI
```

El túnel expone el backend de forma segura a través de HTTPS sin requerir IP pública
ni configuración de red en el entorno donde corre el servidor.
Ver [`infra/README.md`](infra/README.md) para la configuración del túnel.

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

```
main          ← producción / entregables estables
dev           ← integración del equipo
feature/<nombre>   ← desarrollo de funcionalidades
fix/<nombre>       ← correcciones
```

### Commits

Usar prefijos descriptivos:

```
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
|---|---|---|
| 1 | Infraestructura y servidor | ✅ Completado |
| 2 | Autenticación y esqueleto Flutter | 🔄 En progreso |
| 3 | Funcionalidad central (notas, turnos) | ⏳ Pendiente |
| 4 | Sincronización offline | ⏳ Pendiente |
| 5 | Voz a texto on-device | ⏳ Pendiente |
| 6 | Integración con sistemas hospitalarios | 🔄 En progreso |