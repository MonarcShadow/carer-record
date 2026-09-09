# Plan de migración a Supabase

Estado: planificado  
Inicio previsto: 2026-09-09  
Infraestructura actual: [`README.md`](README.md)

## Propósito

Este documento define el plan operativo para migrar Carer Record desde la
persistencia y los servicios ejecutados en una Raspberry Pi hacia Supabase y un
despliegue cloud de FastAPI.

El documento `infra/README.md` describe cómo operar la infraestructura actual.
Este archivo define por separado la arquitectura objetivo, el alcance, impacto,
riesgos, secuencia de implementación, validaciones y estrategia de rollback.
Debe actualizarse a medida que avance la migración.

## Contexto

El sistema actual utiliza una Raspberry Pi como servidor central:

```text
Flutter -> Cloudflare Tunnel -> FastAPI -> MariaDB
                                      -> disco local para audio
                                      -> worker local de Whisper
```

Esta arquitectura permite operar el prototipo, pero mantiene dependencias sobre
la energía, conectividad, almacenamiento y capacidad de un único dispositivo.
También obliga a administrar MariaDB, rutas locales, procesos `systemd`, copias
de seguridad y acceso remoto.

La arquitectura objetivo será:

```text
Flutter -> Supabase Auth
Flutter -> FastAPI cloud -> PostgreSQL de Supabase
                         -> Supabase Storage
                         -> worker de transcripción opcional

Hospital -> gateway/adaptador -> FastAPI o repositorio de ingesta -> Supabase
```

Supabase reemplazará la infraestructura de datos, pero no la lógica de negocio
ni los adaptadores. FastAPI continuará siendo la API principal para Flutter y el
punto de normalización de las integraciones clínicas.

La Raspberry Pi podrá mantenerse como gateway opcional para Mirth, HL7v2 u
otros conectores que deban operar dentro de una red hospitalaria. No continuará
como base de datos ni backend central.

## Objetivos

- Migrar MariaDB a PostgreSQL administrado por Supabase.
- Mantener inicialmente los contratos HTTP actuales de FastAPI.
- Migrar identidad y sesiones desde JWT propio hacia Supabase Auth.
- Reemplazar rutas locales de audio por objetos privados en Supabase Storage.
- Desacoplar los procesos FHIR y HL7v2 de `mysql.connector`.
- Conservar los identificadores existentes y la procedencia de los datos.
- Preparar el modelo para múltiples hospitales y fuentes de información.
- Permitir que una interrupción del gateway local no afecte a la API central.
- Ejecutar un corte verificable y con posibilidad de rollback.

## Fuera de alcance inicial

- Reescribir toda la aplicación Flutter durante la migración de la base de datos.
- Conectar Flutter directamente a las tablas clínicas de Supabase.
- Activar Realtime antes de estabilizar persistencia, autorización y sincronización.
- Implementar un Master Patient Index entre hospitales.
- Escribir información de vuelta a los sistemas clínicos de origen.
- Implementar sincronización offline completa con Drift en la misma entrega.
- Eliminar la Raspberry Pi si todavía es necesaria como gateway hospitalario.
- Convertir todos los identificadores y tipos históricos en una sola operación.

## Decisiones recomendadas

| Tema | Decisión inicial | Motivo |
| --- | --- | --- |
| Acceso a datos | Flutter consume datos mediante FastAPI | Mantiene los contratos actuales y concentra autorización y negocio |
| Autenticación | Flutter autentica con Supabase Auth y envía el JWT a FastAPI | Evita mantener dos sistemas de sesiones |
| Persistencia backend | SQLAlchemy con controlador PostgreSQL | Minimiza cambios en las rutas actuales |
| Migración de datos | Ventana breve de solo lectura y corte único | La doble escritura agrega riesgo y no se justifica inicialmente |
| Esquema | Migraciones SQL versionadas | Permite reproducir, revisar y revertir cambios |
| Identificadores | Preservar los UUID existentes | Evita reconstruir relaciones y referencias móviles |
| Integraciones | Repositorio de ingesta común o API interna | Elimina conexiones directas y SQL duplicado en adaptadores |
| Audio | Bucket privado y claves de objeto en la base | Evita rutas dependientes del host |
| Raspberry Pi | Gateway opcional, sin persistencia central | Conserva conectividad local sin mantener un punto único de falla |
| Corte | Primero datos, luego Auth y Storage | Reduce la cantidad de variables cambiadas simultáneamente |

Estas decisiones pueden ajustarse antes de implementar cada fase, pero deben
quedar registradas en este documento para evitar arquitecturas mixtas no
intencionales.

## Impacto por componente

### Base de datos

Impacto: alto.

El esquema de `backend/app/core/init_db.sql` usa características de MariaDB que
no son directamente compatibles con PostgreSQL:

- `CREATE DATABASE`, `USE`, `ENGINE` y opciones de collation.
- `ENUM` definidos dentro de cada columna.
- `DATETIME` y timestamps sin una política explícita de zona horaria.
- `ON UPDATE CURRENT_TIMESTAMP`.
- `INSERT IGNORE`.
- `ON DUPLICATE KEY UPDATE`.
- Índices declarados dentro de `CREATE TABLE` con sintaxis de MariaDB.

La migración debe crear un esquema PostgreSQL equivalente mediante migraciones
versionadas. Para reducir el riesgo inicial, los UUID existentes deben
preservarse. La conversión de columnas `VARCHAR(36)` al tipo nativo `uuid` puede
hacerse durante la importación si todos los valores son válidos; de lo contrario,
se deben conservar como texto y aplazar esa mejora.

Todos los timestamps nuevos deben almacenarse en UTC. Antes de convertir los
timestamps históricos se debe confirmar en qué zona horaria fueron escritos por
MariaDB y por los dispositivos.

### Modelo multihospital

Impacto: alto.

La unicidad actual de identificadores externos no incluye hospital ni fuente.
Esto puede provocar colisiones cuando dos sistemas utilicen el mismo
`external_id`.

El esquema objetivo debe introducir, como mínimo:

- `hospitals`.
- `data_sources`.
- `profiles`.
- `hospital_memberships`.
- `sync_runs` o una tabla equivalente para el estado de sincronización.

Las entidades importadas deben registrar `hospital_id`, `data_source_id` y su
procedencia. La clave lógica de un recurso externo será:

```text
(hospital_id, data_source_id, resource_type, external_id)
```

No se deben fusionar pacientes de distintos hospitales automáticamente.

### FastAPI

Impacto: medio.

La API usa SQLAlchemy y consultas parametrizadas con `sqlalchemy.text`, por lo
que gran parte de las rutas puede conservarse. Los principales cambios serán:

- Reemplazar PyMySQL por un controlador PostgreSQL compatible con SQLAlchemy.
- Configurar la conexión de Supabase y su pool apropiado para el proveedor cloud.
- Añadir `pool_pre_ping` y límites de pool adecuados al plan contratado.
- Revisar transacciones, rollback y manejo de errores de integridad.
- Validar el JWT emitido por Supabase en cada endpoint protegido.
- Obtener rol, hospital y estado activo desde el dominio, no desde datos enviados por Flutter.
- Mantener las respuestas actuales durante la primera etapa para no bloquear Flutter.

Actualmente las rutas de usuarios, pacientes y notas no aplican una dependencia
de autorización aunque exista un token emitido en el login. La migración no se
considerará completa hasta proteger esos endpoints y comprobar aislamiento por
hospital.

### Sincronización FHIR

Impacto: alto.

`backend/app/sync/sync_service.py` depende directamente de `mysql.connector`,
placeholders `%s`, commits manuales y SQL específico de MariaDB. También guarda
el avance en `fhir_sync_state.json`.

Debe adaptarse para:

- Usar PostgreSQL mediante el repositorio de persistencia compartido.
- Reemplazar `ON DUPLICATE KEY UPDATE` por `ON CONFLICT ... DO UPDATE`.
- Mantener upserts idempotentes con la clave completa de procedencia.
- Guardar checkpoints y resultados de ejecución en PostgreSQL.
- Asociar cada ejecución a un hospital y una fuente.
- Registrar errores recuperables sin perder el checkpoint anterior.
- Evitar que dos workers procesen simultáneamente el mismo origen.

El mapeo FHIR puede mantenerse, pero no debe continuar acoplado a cursores de
MySQL como interfaz permanente.

### Adaptadores FHIR y HL7v2

Impacto: alto.

Existen implementaciones que escriben directamente en MariaDB:

- `backend/app/fhir/fhir_adapter.py`.
- `integration/adapters/fhir_adapter.py`.
- `integration/adapters/hl7v2_adapter.py`.

Los dos adaptadores FHIR contienen lógica duplicada. Antes o durante la
migración se debe elegir una implementación canónica para evitar corregir dos
veces cada consulta.

El gateway local no debe recibir credenciales administrativas generales de
Supabase. La alternativa recomendada es enviar lotes normalizados a un endpoint
de ingesta autenticado de FastAPI. Si temporalmente se permite conexión directa,
debe utilizar un usuario PostgreSQL restringido a las tablas y operaciones de
ingesta.

### Autenticación y usuarios

Impacto: alto.

El flujo actual consulta `users.password_hash`, valida bcrypt y emite un JWT
firmado con `SECRET_KEY`. Flutter guarda ese token y otros datos de sesión en
`SharedPreferences`.

El flujo objetivo será:

```text
Flutter -> Supabase Auth -> access token
Flutter -> FastAPI -> Authorization: Bearer <access token>
FastAPI -> validación JWT -> perfil y membresía -> operación autorizada
```

La tabla de dominio no debe duplicar contraseñas. Para preservar las relaciones
existentes, `profiles.id` mantendrá el ID del usuario actual y
`profiles.auth_user_id` referenciará de forma única a `auth.users.id`.
`hospital_memberships.profile_id` resolverá los permisos dentro de cada
hospital. Así, referencias como `notes.author_id` pueden seguir apuntando al ID
de dominio sin depender del identificador asignado por Supabase Auth.

No se debe escribir directamente en el esquema interno `auth` de Supabase para
importar usuarios. Para el prototipo se recomienda crear o invitar usuarios con
la API administrativa y solicitar restablecimiento de contraseña. La migración
de perfiles debe conservar una tabla temporal de correspondencia entre el ID
de dominio y el nuevo `auth.users.id`.

El login por RUT requiere una decisión explícita. Supabase Auth trabaja de forma
nativa con email y contraseña. La opción inicial recomendada es usar email para
autenticación y mantener el RUT como dato único del perfil. Si el login por RUT
es obligatorio, FastAPI puede resolver el email asociado y actuar como fachada
temporal, sin volver a almacenar ni validar hashes propios.

FastAPI debe validar al menos firma, emisor, audiencia y expiración del JWT. Las
credenciales administrativas o `service_role` nunca deben incorporarse en
Flutter ni en archivos versionados.

### Flutter

Impacto: medio.

La navegación y las pantallas pueden mantenerse. Los cambios principales serán:

- Integrar el SDK de Supabase para login, renovación y cierre de sesión.
- Reemplazar el login contra `/api/v1/auth/login` cuando Supabase Auth esté listo.
- Adjuntar el access token a todas las solicitudes hacia FastAPI.
- Manejar expiración, renovación, revocación y ausencia de sesión.
- Evitar persistir tokens sensibles directamente en `SharedPreferences`.
- Actualizar la URL base cuando FastAPI tenga un dominio cloud estable.

Los servicios actuales de usuarios, pacientes y notas no envían el encabezado
`Authorization`. Deben pasar por un cliente HTTP compartido o interceptor antes
de activar la protección del backend.

La implementación de Drift/SQLite debe tratarse como una fase posterior. No es
un requisito para cambiar la base central, pero sí lo es para cumplir la meta de
operación offline-first.

### Audio y transcripción

Impacto: alto.

`backend/app/api/v1/routes/notes.py` escribe audio en
`/home/pi/carer-record-audio`, y `backend/app/workers/whisper_worker.py` procesa
esa misma ruta. Esto no funcionará cuando API y worker estén en instancias
distintas o efímeras.

La solución objetivo debe:

- Crear un bucket privado para audio.
- Guardar en `notes` una clave de objeto, no una ruta absoluta ni una URL firmada.
- Subir el objeto antes de confirmar la nota o limpiar el objeto si falla la transacción.
- Descargar el audio a un archivo temporal cuando el worker lo procese.
- Eliminar siempre el archivo temporal después de procesarlo.
- Mantener estados `pending`, `processing`, `done` y `error`.
- Evitar que dos workers reclamen la misma nota.
- Validar extensión, MIME, tamaño máximo y autorización de descarga.
- Definir retención y eliminación para audios clínicos.

Las URLs firmadas deben generarse bajo demanda y con expiración breve. No deben
persistirse porque dejan de ser válidas.

### Infraestructura y operación

Impacto: medio-alto.

Supabase no ejecuta FastAPI ni el worker de Whisper. Ambos requieren un proveedor
de aplicaciones o una máquina virtual. El despliegue debe incluir:

- Variables y secretos separados por ambiente.
- URL HTTPS estable para FastAPI.
- Política CORS explícita.
- Health checks independientes para API, base de datos y Storage.
- Logs sin contraseñas, tokens, audios ni contenido clínico.
- Alertas básicas para errores de API, sincronización y trabajos pendientes.
- Backups y política de recuperación acordes al plan de Supabase elegido.

## Inventario de archivos afectados

| Archivo | Cambio esperado |
| --- | --- |
| `backend/app/core/config.py` | Configuración PostgreSQL, Auth, Storage y ambientes |
| `backend/app/core/database.py` | Engine PostgreSQL, pool y manejo de sesiones |
| `backend/app/core/init_db.sql` | Mantener como referencia MariaDB; crear migraciones PostgreSQL separadas |
| `backend/app/core/security.py` | Retirar emisión propia y validar JWT de Supabase |
| `backend/app/api/v1/routes/auth.py` | Retirar o convertir el login en fachada temporal |
| `backend/app/api/v1/routes/users.py` | Separar identidad Auth de perfil y membresía |
| `backend/app/api/v1/routes/patients.py` | Aplicar autorización y aislamiento por hospital |
| `backend/app/api/v1/routes/notes.py` | Usar Storage y autorización por hospital/paciente |
| `backend/app/sync/sync_service.py` | PostgreSQL, checkpoints centrales e idempotencia |
| `backend/app/fhir/fhir_adapter.py` | Eliminar conexión MySQL directa o consolidar implementación |
| `backend/app/workers/whisper_worker.py` | Storage remoto y reclamo seguro de trabajos |
| `backend/requirements.txt` | Controlador PostgreSQL y dependencias de Supabase/JWT necesarias |
| `integration/adapters/fhir_adapter.py` | Usar ingesta central y eliminar SQL MySQL duplicado |
| `integration/adapters/hl7v2_adapter.py` | Enviar a ingesta central o usar repositorio restringido |
| `app/lib/data/remote/auth_service.dart` | Supabase Auth |
| `app/lib/data/local/auth_preferences.dart` | Sesión administrada de forma segura |
| `app/lib/data/remote/*_service.dart` | Enviar Bearer token y manejar 401/403 |
| `app/lib/core/config.dart` | URL estable y configuración por ambiente |
| `app/pubspec.yaml` | Dependencias de Supabase y almacenamiento seguro |

## Riesgos y mitigaciones

| Riesgo | Nivel | Mitigación |
| --- | --- | --- |
| Pérdida o corrupción durante la transferencia | Alto | Backup verificable, importación de ensayo, conteos, integridad referencial y ventana de solo lectura |
| Colisiones de IDs externos entre hospitales | Alto | Clave compuesta con hospital, fuente, tipo e ID externo |
| Endpoints accesibles sin autorización | Alto | Dependencia de autenticación común y pruebas 401/403 antes del corte |
| Usuarios sin acceso después de migrar Auth | Alto | Invitaciones o reset previo, tabla de correspondencia y usuario administrador de emergencia |
| Ruptura del login por RUT | Alto | Decidir flujo antes de migrar usuarios y comunicar uso de email si corresponde |
| Duplicación en sincronización FHIR | Alto | Upserts idempotentes, checkpoints transaccionales y pruebas de reejecución |
| Worker procesa dos veces el mismo audio | Alto | Reclamo atómico del trabajo y bloqueo de fila o estado condicional |
| Audios huérfanos o inaccesibles | Medio-alto | Bucket privado, compensación ante fallos y reconciliación objeto-registro |
| Agotamiento de conexiones PostgreSQL | Medio-alto | Pooler, límites de pool, timeouts y métricas de conexiones |
| Diferencias de zona horaria | Medio | Definir UTC y validar muestras históricas antes de convertir |
| Dependencia total de Internet | Medio | Mantener caché/offline como fase posterior y gateway local para integraciones |
| Exposición de secretos de Supabase | Alto | Secret manager, rotación y prohibición de `service_role` en Flutter |
| Costos o límites del plan | Medio | Medir DB, Storage, transferencia, conexiones y ejecución del worker |
| Rollback con escrituras nuevas en cloud | Alto | Mantener ventana controlada y exportar deltas antes de reabrir MariaDB |
| Falta de pruebas existentes | Alto | Crear pruebas mínimas de API, ingesta, Auth y Storage antes del corte |

## Prerrequisitos

Antes de implementar cambios se debe confirmar:

- [ ] Proyecto Supabase de desarrollo creado en una región aceptable para el proyecto.
- [ ] Ambiente de staging separado o estrategia clara para no probar con datos reales.
- [ ] Responsable y propietario del proyecto Supabase definidos.
- [ ] Acceso administrativo protegido con MFA.
- [ ] Clasificación de los datos y restricciones institucionales revisadas.
- [ ] Política de retención, backup y restauración definida.
- [ ] Proveedor para FastAPI y worker seleccionado.
- [ ] Dominio o URL estable para la API definido.
- [ ] Flujo de login por email o RUT decidido.
- [ ] Inventario de usuarios y estrategia de activación confirmados.
- [ ] Zona horaria histórica de MariaDB confirmada.
- [ ] Volumen actual de tablas y audios medido.
- [ ] Backup completo de MariaDB restaurado con éxito en un entorno de prueba.
- [ ] Secretos actuales identificados para posterior rotación.

## Plan de implementación

### Fase 0: línea base y seguridad de la migración

Objetivo: asegurar que el estado actual sea recuperable y medible.

- [ ] Registrar versión desplegada de Flutter, FastAPI, worker y adaptadores.
- [ ] Exportar estructura y datos de MariaDB.
- [ ] Copiar y verificar el directorio de audios.
- [ ] Probar la restauración de MariaDB en un entorno aislado.
- [ ] Obtener conteos por tabla y tamaños aproximados.
- [ ] Detectar claves foráneas rotas y registros huérfanos.
- [ ] Registrar la zona horaria del servidor y de MariaDB.
- [ ] Ejecutar smoke tests manuales de login, usuarios, pacientes, notas y audio.
- [ ] Guardar resultados como evidencia de línea base.
- [ ] Definir responsable y duración máxima de la ventana de corte.

Criterio de salida: existe un backup restaurable y una línea base con la que
comparar Supabase.

### Fase 1: proyecto Supabase y ambientes

Objetivo: preparar infraestructura sin modificar producción.

- [ ] Crear proyecto y registrar región, plan y responsables.
- [ ] Habilitar MFA para administradores.
- [ ] Instalar y configurar Supabase CLI para migraciones locales/versionadas.
- [ ] Separar configuración de desarrollo, staging y producción.
- [ ] Guardar secretos en el proveedor de despliegue, no en Git.
- [ ] Definir conexión directa para migraciones y conexión compatible con pooler para la API.
- [ ] Configurar límites y timeouts de conexión.
- [ ] Crear un bucket privado de audio en staging.
- [ ] Definir política inicial de backups y restauración.
- [ ] Confirmar que ninguna credencial administrativa llegará a Flutter.

Criterio de salida: staging puede ejecutar una migración vacía, FastAPI puede
abrir una conexión de prueba y Storage permanece privado.

### Fase 2: esquema PostgreSQL versionado

Objetivo: reproducir el modelo actual y agregar el contexto multihospital.

- [ ] Crear migraciones para tablas, claves foráneas, índices y restricciones.
- [ ] Crear `hospitals`, `data_sources`, `profiles` y `hospital_memberships`.
- [ ] Preservar `profiles.id` y agregar `profiles.auth_user_id` nullable y único.
- [ ] Mantener las referencias clínicas, como `notes.author_id`, sobre `profiles.id`.
- [ ] Crear `sync_runs` o estructura equivalente para checkpoints.
- [ ] Asociar entidades clínicas a hospital y fuente cuando corresponda.
- [ ] Reemplazar enums MariaDB por enums PostgreSQL o restricciones `CHECK`.
- [ ] Definir timestamps UTC y mecanismo de actualización de `updated_at`.
- [ ] Implementar unicidad por procedencia para recursos importados.
- [ ] Definir borrado en cascada de forma explícita.
- [ ] Habilitar RLS en tablas expuestas por las APIs de Supabase.
- [ ] Denegar acceso directo de clientes a tablas clínicas durante la primera etapa.
- [ ] Crear un rol de backend con privilegios mínimos o documentar el uso controlado del rol de servicio.
- [ ] Crear datos semilla para hospital y fuente actuales.
- [ ] Ejecutar migraciones desde cero en una base limpia.
- [ ] Probar rollback de migraciones que todavía no contienen datos productivos.

Criterio de salida: una base vacía puede reconstruirse únicamente desde el
repositorio y representa todas las relaciones necesarias.

### Fase 3: compatibilidad de FastAPI con PostgreSQL

Objetivo: ejecutar la API actual sobre PostgreSQL sin cambiar todavía Auth ni
Storage.

- [ ] Agregar el controlador PostgreSQL elegido a `backend/requirements.txt`.
- [ ] Cambiar la configuración predeterminada para no incluir credenciales locales.
- [ ] Configurar engine, pool, timeouts y `pool_pre_ping`.
- [ ] Mantener `get_db` como punto común de sesión.
- [ ] Adaptar consultas incompatibles y errores de integridad.
- [ ] Asegurar rollback en excepciones de escritura.
- [ ] Revisar que fechas, booleanos y resultados mantengan el JSON esperado.
- [ ] Mantener contratos de usuarios, pacientes y notas.
- [ ] Agregar pruebas de integración contra PostgreSQL limpio.
- [ ] Separar health check general de disponibilidad de dependencias si es necesario.

Criterio de salida: las rutas actuales pasan pruebas sobre PostgreSQL de staging
sin depender de MariaDB.

### Fase 4: transferencia y reconciliación de datos

Objetivo: demostrar que la información actual puede copiarse sin pérdida.

Orden recomendado de importación:

```text
hospitals y data_sources
usuarios actuales hacia profiles, inicialmente sin auth_user_id
patients
encounters, conditions, medications, observations y allergies
procedures, immunizations, diagnostic_reports e imaging_studies
care_plans, care_teams y care_team_members
notes y shift_changes
hl7v2_raw_messages, fhir_sync_log y estado de sincronización
```

- [ ] Crear un script repetible de extracción, transformación y carga.
- [ ] Preservar IDs primarios de dominio y relaciones existentes.
- [ ] Mantener una correspondencia separada para los IDs creados por Supabase Auth.
- [ ] Asignar hospital y fuente actuales a todos los registros históricos.
- [ ] Convertir enums y valores inválidos de forma explícita y auditable.
- [ ] Convertir timestamps solo después de confirmar su zona de origen.
- [ ] Registrar filas rechazadas sin descartarlas silenciosamente.
- [ ] Ejecutar una importación completa de ensayo en staging.
- [ ] Comparar conteos por tabla entre MariaDB y PostgreSQL.
- [ ] Verificar claves foráneas y registros huérfanos.
- [ ] Comparar muestras determinísticas de cada tabla.
- [ ] Validar pacientes con todas sus secciones clínicas.
- [ ] Validar notas con autores y orden temporal.
- [ ] Medir duración para estimar la ventana de corte.
- [ ] Repetir la importación desde cero para comprobar reproducibilidad.

Criterio de salida: dos ejecuciones limpias producen los mismos conteos y las
validaciones funcionales no muestran pérdida ni asociaciones incorrectas.

### Fase 5: ingesta FHIR y HL7v2

Objetivo: eliminar las dependencias directas de MariaDB y conservar la
idempotencia.

- [ ] Elegir una implementación FHIR canónica.
- [ ] Extraer persistencia de la lógica de mapeo clínico.
- [ ] Implementar upserts PostgreSQL con `ON CONFLICT`.
- [ ] Incorporar hospital y fuente en búsquedas y restricciones únicas.
- [ ] Guardar checkpoints en PostgreSQL.
- [ ] Registrar inicio, fin, conteos y errores de cada sync run.
- [ ] Impedir ejecuciones concurrentes para una misma fuente.
- [ ] Probar primera carga completa.
- [ ] Probar sincronización incremental.
- [ ] Reejecutar el mismo bundle y comprobar que no crea duplicados.
- [ ] Probar fallo a mitad de página y recuperación posterior.
- [ ] Decidir si el gateway llama una API interna o usa un rol DB restringido.
- [ ] Rotar y limitar las credenciales entregadas al gateway.

Criterio de salida: FHIR y HL7v2 escriben en staging sin MySQL, son idempotentes
y recuperan su estado después de un reinicio.

### Fase 6: Supabase Storage y worker de audio

Objetivo: retirar la dependencia de `/home/pi/carer-record-audio`.

- [ ] Definir bucket privado, límite de tamaño, MIME permitidos y retención.
- [ ] Definir claves de objeto con UUID sin nombres clínicos visibles.
- [ ] Cambiar `audio_path` por una clave de objeto o agregar una columna nueva durante la transición.
- [ ] Implementar subida y compensación si la creación de la nota falla.
- [ ] Generar descargas autorizadas o URLs firmadas de corta duración.
- [ ] Adaptar el worker para descargar a un directorio temporal.
- [ ] Eliminar temporales aun cuando Whisper falle.
- [ ] Implementar reclamo atómico de notas pendientes.
- [ ] Evitar que una nota quede indefinidamente en `processing`.
- [ ] Probar estados `pending`, `processing`, `done` y `error`.
- [ ] Probar audio inexistente, corrupto y demasiado grande.
- [ ] Crear una tarea de reconciliación para objetos huérfanos.

Criterio de salida: API y worker pueden ejecutarse en hosts distintos y procesar
audio sin compartir disco.

### Fase 7: Supabase Auth y autorización

Objetivo: reemplazar las credenciales y JWT propios sin perder acceso de
usuarios.

- [ ] Definir definitivamente login por email o compatibilidad temporal con RUT.
- [ ] Crear usuarios de staging mediante la API administrativa soportada.
- [ ] Completar `profiles.auth_user_id` con la correspondencia de cada usuario.
- [ ] Verificar que cada usuario activo tenga perfil y membresía válidos.
- [ ] Implementar validación JWT en FastAPI.
- [ ] Implementar una dependencia común para endpoints protegidos.
- [ ] Aplicar autorización por rol, hospital y estado activo.
- [ ] Proteger usuarios, pacientes, notas, audio e ingesta.
- [ ] Confirmar respuestas 401 para token ausente, inválido o expirado.
- [ ] Confirmar respuestas 403 para rol u hospital incorrecto.
- [ ] Integrar Supabase Auth en Flutter.
- [ ] Centralizar cliente HTTP e incluir Bearer token en todas las solicitudes.
- [ ] Manejar renovación, logout y revocación de sesión.
- [ ] Migrar tokens fuera de `SharedPreferences` si el SDK no los protege adecuadamente.
- [ ] Preparar invitación o reset para los usuarios actuales.
- [ ] Crear y verificar un administrador de emergencia antes del corte.
- [ ] Retirar hashes y emisión JWT propios solo después de validar el flujo nuevo.

Criterio de salida: todos los endpoints sensibles exigen una identidad válida y
no existe acceso cruzado entre hospitales.

### Fase 8: despliegue cloud y ensayo de corte

Objetivo: validar el sistema completo en condiciones equivalentes a producción.

- [ ] Desplegar FastAPI con secretos administrados por el proveedor.
- [ ] Desplegar worker si la transcripción de servidor continúa habilitada.
- [ ] Configurar URL HTTPS, CORS y health checks.
- [ ] Actualizar una compilación de Flutter para apuntar a staging.
- [ ] Ejecutar smoke tests desde un dispositivo real y una red externa.
- [ ] Probar login, listado, detalle, creación de nota, audio y confirmación.
- [ ] Ejecutar sincronización FHIR y un mensaje HL7v2 de prueba.
- [ ] Reiniciar API y worker para comprobar recuperación.
- [ ] Verificar logs y confirmar que no contienen información sensible.
- [ ] Medir latencia, conexiones, errores y trabajos pendientes.
- [ ] Ejecutar un simulacro completo con backup, importación, validación y rollback.
- [ ] Documentar duración y problemas del simulacro.

Criterio de salida: el simulacro cumple todos los criterios de validación y el
rollback ha sido probado, no solo descrito.

### Fase 9: corte de producción

Objetivo: cambiar el sistema activo con una ventana controlada.

- [ ] Comunicar inicio y duración estimada de mantenimiento.
- [ ] Detener escrituras de Flutter, FastAPI, worker y adaptadores.
- [ ] Confirmar que no queden transacciones ni trabajos en curso.
- [ ] Crear backup final de MariaDB y audios.
- [ ] Ejecutar exportación e importación final.
- [ ] Ejecutar reconciliación automática de conteos y relaciones.
- [ ] Ejecutar validación funcional con datos conocidos.
- [ ] Activar FastAPI y worker cloud.
- [ ] Cambiar Flutter o DNS hacia la URL estable.
- [ ] Activar adaptadores contra el nuevo destino.
- [ ] Monitorear errores, conexiones, sincronización y cola de audio.
- [ ] Mantener MariaDB sin escrituras durante el periodo de observación.
- [ ] Registrar hora, versión, responsables y resultado del corte.

Criterio de salida: el sistema opera sobre Supabase, las validaciones son
correctas y no se detectan errores críticos durante el periodo acordado.

### Fase 10: estabilización y retiro de infraestructura anterior

Objetivo: cerrar la migración sin perder capacidad de recuperación.

- [ ] Resolver errores y datos rechazados detectados durante el corte.
- [ ] Confirmar backups automáticos y realizar una restauración de prueba.
- [ ] Rotar secretos usados por MariaDB, Cloudflare y scripts antiguos.
- [ ] Retirar el endpoint de login y JWT propios.
- [ ] Retirar conexiones MySQL y dependencias que ya no se utilicen.
- [ ] Archivar `fhir_sync_state.json` después de validar checkpoints cloud.
- [ ] Mantener MariaDB apagado pero recuperable durante el periodo acordado.
- [ ] Retirar Cloudflare Tunnel como acceso principal.
- [ ] Mantener en la Raspberry solo los servicios de gateway necesarios.
- [ ] Actualizar documentación operativa y diagramas con el estado real.
- [ ] Abrir una fase separada para Drift/SQLite y sincronización offline.

Criterio de salida: no existen escrituras ni dependencias ocultas sobre MariaDB,
el disco local o el túnel anterior.

## Validación mínima antes del corte

No existen pruebas automatizadas suficientes en el repositorio actual. Como
mínimo, deben incorporarse o ejecutarse estas validaciones antes de migrar
producción.

### Persistencia

- [ ] Esquema reproducible desde una base vacía.
- [ ] Conteos iguales entre origen y destino.
- [ ] Cero claves foráneas huérfanas.
- [ ] Restricciones únicas probadas.
- [ ] Fechas históricas correctas en UTC y presentación local.
- [ ] Escrituras concurrentes básicas sin pérdida.

### API

- [ ] Health check con DB disponible y no disponible.
- [ ] Listar, crear, actualizar y eliminar usuarios según rol.
- [ ] Listar pacientes y recuperar todas sus secciones.
- [ ] Crear, listar y confirmar notas.
- [ ] Manejar duplicados como 409 y ausencias como 404.
- [ ] Hacer rollback ante una escritura incompleta.

### Seguridad

- [ ] Token ausente, inválido, expirado y revocado.
- [ ] Usuario inactivo.
- [ ] Rol insuficiente.
- [ ] Acceso cruzado entre hospitales denegado.
- [ ] Tablas clínicas inaccesibles directamente para clientes no autorizados.
- [ ] Bucket privado y descargas con autorización.
- [ ] Secretos ausentes en aplicación, repositorio y logs.

### Integraciones

- [ ] Bundle FHIR nuevo.
- [ ] Bundle FHIR repetido sin duplicados.
- [ ] Actualización incremental de un recurso.
- [ ] Recuperación después de fallo parcial.
- [ ] Mensaje HL7v2 válido, repetido e inválido.
- [ ] Checkpoint separado por hospital y fuente.

### Audio

- [ ] Subida desde Flutter.
- [ ] Descarga autorizada.
- [ ] Transcripción completada.
- [ ] Reintento después de error.
- [ ] Reclamo de trabajo con dos workers simultáneos.
- [ ] Limpieza de archivos temporales y objetos huérfanos.

## Observabilidad

Durante staging, corte y estabilización se deben observar al menos:

- Tasa de respuestas 4xx y 5xx de FastAPI.
- Latencia de endpoints de pacientes y notas.
- Conexiones PostgreSQL activas y errores del pool.
- Errores de autenticación y autorización.
- Última sincronización correcta por hospital y fuente.
- Cantidad de recursos importados, omitidos y fallidos.
- Notas de audio por estado y antigüedad de las pendientes.
- Errores de subida y descarga en Storage.
- Consumo de base de datos, Storage y transferencia.

Las alertas no deben incluir datos identificables del paciente ni contenido de
notas o transcripciones.

## Estrategia de rollback

El rollback debe ejecutarse si aparece cualquiera de estas condiciones durante
el corte:

- Reconciliación de datos incompleta o inconsistente.
- Login inaccesible para administradores o usuarios de prueba.
- Acceso no autorizado entre hospitales o roles.
- Fallo generalizado de creación o lectura de notas.
- Sincronización que duplica o pierde recursos.
- Error de Storage que impide conservar audios nuevos.
- Incapacidad de estabilizar conexiones o latencia dentro de la ventana.

Procedimiento:

1. Detener nuevas escrituras en FastAPI cloud y adaptadores.
2. Registrar el momento exacto y exportar cualquier escritura creada en Supabase.
3. Cambiar Flutter o DNS nuevamente hacia FastAPI en la Raspberry Pi.
4. No reabrir MariaDB hasta identificar y aplicar o descartar explícitamente el delta cloud.
5. Restaurar el backup final solo si la base original fue modificada o dañada.
6. Reanudar worker y adaptadores locales después de validar conectividad.
7. Ejecutar smoke tests del sistema anterior.
8. Documentar causa, datos afectados y condición necesaria para un nuevo intento.

MariaDB y el directorio local de audios deben mantenerse intactos y sin
escrituras durante el periodo inicial de observación. No deben eliminarse el
mismo día del corte.

## Checklist para el primer día

El primer día debe reducir incertidumbre y no intentar completar el corte.

- [ ] Confirmar las decisiones pendientes: región, ambientes, proveedor cloud y login por RUT/email.
- [ ] Crear Supabase de desarrollo o staging con MFA.
- [ ] Obtener backup de MariaDB y comprobar que puede restaurarse.
- [ ] Medir conteos, tamaños, zona horaria y volumen de audios.
- [ ] Inicializar migraciones versionadas de Supabase.
- [ ] Crear primero tablas de hospital, fuente, perfiles y membresías.
- [ ] Portar una tabla simple y una relacionada, por ejemplo `patients` y `notes`.
- [ ] Conectar FastAPI de forma local a PostgreSQL de staging.
- [ ] Ejecutar una ruta de lectura y una de escritura sin cambiar Flutter.
- [ ] Registrar bloqueadores encontrados y ajustar las fases siguientes.

Resultado esperado del primer día: infraestructura de staging disponible,
backup validado, primeras migraciones versionadas y FastAPI conectado a
PostgreSQL sin afectar el entorno actual.

## Criterio de finalización

La migración se considerará completa cuando:

- [ ] PostgreSQL de Supabase sea la única base central activa.
- [ ] FastAPI y el worker no dependan del host ni del disco de la Raspberry Pi.
- [ ] Flutter use Supabase Auth y envíe tokens válidos a FastAPI.
- [ ] Todos los endpoints clínicos apliquen autenticación y autorización.
- [ ] Los datos estén aislados por hospital y fuente.
- [ ] FHIR y HL7v2 sean idempotentes y no usen conexiones MySQL.
- [ ] Los audios estén en un bucket privado con acceso controlado.
- [ ] Backups, restauración, métricas y alertas estén verificados.
- [ ] El rollback haya sido ensayado.
- [ ] MariaDB y Cloudflare Tunnel puedan retirarse sin interrumpir el sistema.
- [ ] La documentación represente el estado realmente desplegado.
