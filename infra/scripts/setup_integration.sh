#!/usr/bin/env bash
# ============================================================
#  Carer Record — Setup de integración
#  Ejecutar en el servidor (sistema Linux):
#    bash infra/scripts/setup_integration.sh
# ============================================================
set -euo pipefail

DB_NAME="carer_record"
DB_USER="carer_user"
DB_PASS="CAMBIAR_EN_PRODUCCION"   # ← cambiar antes de ejecutar

echo "=== [1/4] Instalando dependencias Python ==="
pip install mysql-connector-python hl7apy --break-system-packages

echo ""
echo "=== [2/4] Creando usuario en la base de datos ==="
sudo mariadb -u root <<SQL
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
SQL
echo "Usuario '${DB_USER}' creado."

echo ""
echo "=== [3/4] Aplicando schema ==="
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
sudo mariadb -u root < "${SCRIPT_DIR}/../../backend/app/core/init_db.sql"
echo "Schema aplicado a '${DB_NAME}'."

echo ""
echo "=== [4/4] Verificando tablas ==="
sudo mariadb -u root -e "USE ${DB_NAME}; SHOW TABLES;"

echo ""
echo "✓ Setup completo."
echo ""
echo "Próximos pasos:"
echo "  1. Generar datos con Synthea (ver integration/README.md)"
echo "  2. Transferir los archivos generados al servidor"
echo "  3. Importar pacientes FHIR:"
echo "     python integration/adapters/fhir_adapter.py --input /ruta/a/synthea_output/fhir/"