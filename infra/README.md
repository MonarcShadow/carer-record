# Infraestructura — Carer Record

Guía para configurar el servidor de desarrollo y el túnel de acceso remoto.
Esta configuración la gestiona un integrante del equipo; los demás solo necesitan
la URL del túnel para configurar su `.env`.

---

## Requisitos en el servidor (sistema Linux)

- MariaDB ≥ 10.x instalado y en ejecución
- Python ≥ 3.11
- `cloudflared` instalado (ver sección siguiente)
- Cuenta en [Cloudflare](https://dash.cloudflare.com) (gratuita)

---

## 1. Instalar cloudflared

```bash
curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64 \
  -o /usr/local/bin/cloudflared
chmod +x /usr/local/bin/cloudflared
```

> Para arquitecturas x86_64 reemplazar `linux-arm64` por `linux-amd64`.

Verificar instalación:

```bash
cloudflared --version
```

---

## 2. Autenticar cloudflared con tu cuenta

```bash
cloudflared tunnel login
```

Se abrirá una URL en el navegador para autorizar el sistema Linux en tu cuenta de
Cloudflare. Las credenciales se guardan en `~/.cloudflared/cert.pem`.

> Estas credenciales **no se versionen**. Están en `.gitignore`.

---

## 3. Crear el túnel

```bash
cloudflared tunnel create carer-record-dev
```

Esto genera un UUID de túnel y un archivo de credenciales en
`~/.cloudflared/<UUID>.json`. Anotar el UUID — se usa en la configuración.

---

## 4. Configurar el túnel

Copiar la plantilla y completarla:

```bash
cp infra/cloudflare/config.yml.example ~/.cloudflared/config.yml
```

Editar `~/.cloudflared/config.yml`:

```yaml
tunnel: <UUID-del-tunel>
credentials-file: /home/<usuario>/.cloudflared/<UUID-del-tunel>.json

ingress:
  - service: http://localhost:8000
```

> El archivo `config.yml` con el UUID **no se versiona**. Solo se versiona
> `config.yml.example` como referencia de estructura.

---

## 5. Iniciar el túnel

```bash
cloudflared tunnel run carer-record-dev
```

La URL pública asignada aparece en la salida:

```text
Your quick Tunnel has been created! Visit it at:
https://<nombre-generado>.cfargotunnel.com
```

Esta URL es la `BACKEND_URL` que el equipo configura en su `.env`.

---

## 6. Ejecutar como servicio del sistema

Para que el túnel inicie automáticamente con el servidor:

```bash
cloudflared service install
systemctl enable cloudflared
systemctl start cloudflared
```

---

## 7. Compartir la URL con el equipo

Una vez activo el túnel, comunicar la URL al equipo para que la agreguen en su
archivo `.env`:

```text
BACKEND_URL=https://<nombre-generado>.cfargotunnel.com
```

La URL de un Named Tunnel **es permanente** — no cambia entre reinicios.

---

## Arquitectura de conectividad

```text
Teléfono (app Flutter)
        │  HTTPS
        ▼
Cloudflare Edge  ──▶  cloudflared (sistema Linux)  ──▶  FastAPI :8000  ──▶  MariaDB
```

El túnel establece una conexión saliente desde el sistema Linux hacia Cloudflare,
por lo que no se requiere IP pública ni apertura de puertos en el router.

---

## Referencia rápida de comandos

| Acción | Comando |
| --- | --- |
| Ver túneles creados | `cloudflared tunnel list` |
| Ver estado del servicio | `systemctl status cloudflared` |
| Ver logs en tiempo real | `journalctl -u cloudflared -f` |
| Detener el túnel | `systemctl stop cloudflared` |
