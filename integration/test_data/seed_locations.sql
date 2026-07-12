-- ============================================================
--  Carer Record — Datos de prueba de ubicación hospitalaria
--  Ejecutar en el servidor:
--    mariadb -u admin -padmin carer_record < seed_locations.sql
-- ============================================================

USE carer_record;

-- Asignar ubicaciones por bloques de pacientes ordenados por id
-- Total: 108 pacientes distribuidos en 8 áreas

SET @row = 0;

UPDATE patients
SET
    ward       = CASE
        WHEN @row < 10  THEN 'UCI'
        WHEN @row < 30  THEN 'Medicina Interna'
        WHEN @row < 50  THEN 'Cirugía'
        WHEN @row < 65  THEN 'Pediatría'
        WHEN @row < 75  THEN 'Maternidad'
        WHEN @row < 90  THEN 'Traumatología'
        WHEN @row < 100 THEN 'Neurología'
        ELSE                 'Pensionado'
    END,
    bed_number = CASE
        WHEN @row < 10  THEN CONCAT('UCI-', LPAD(@row + 1, 2, '0'))
        WHEN @row < 30  THEN CONCAT('MI-',  LPAD(@row - 9,  2, '0'))
        WHEN @row < 50  THEN CONCAT('CIR-', LPAD(@row - 29, 2, '0'))
        WHEN @row < 65  THEN CONCAT('PED-', LPAD(@row - 49, 2, '0'))
        WHEN @row < 75  THEN CONCAT('MAT-', LPAD(@row - 64, 2, '0'))
        WHEN @row < 90  THEN CONCAT('TRA-', LPAD(@row - 74, 2, '0'))
        WHEN @row < 100 THEN CONCAT('NEU-', LPAD(@row - 89, 2, '0'))
        ELSE                 CONCAT('PEN-', LPAD(@row - 99, 2, '0'))
    END,
    admission_date = DATE_SUB(NOW(), INTERVAL FLOOR(RAND(42) * 30) DAY)
WHERE (@row := @row + 1) IS NOT NULL;

-- Verificar distribución
SELECT ward, COUNT(*) as pacientes, MIN(bed_number) as primera_cama, MAX(bed_number) as ultima_cama
FROM patients
GROUP BY ward
ORDER BY pacientes DESC;
