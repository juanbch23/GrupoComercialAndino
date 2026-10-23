# Cómo replicar el proyecto Grupo Comercial Andino en otra PC (desde cero)

Al terminar tendrás en tu computadora:
- las bases **`STAGE_GCA`** y **`DWH_GCA`** en SQL Server, cargadas y limpias;
- la solución **`GCA.sln`** en Visual Studio, con los proyectos SSIS `stage_GCA`, `DWH_GCA` y el tabular `Tabular_GCA`;
- el cubo **`Tabular_GCA`** en Analysis Services, con 83 medidas DAX, listo para conectar Power BI.

> Este proyecto usa **sus propias bases** (`STAGE_GCA`, `DWH_GCA`, `Tabular_GCA`) y no toca las de otros proyectos
> (por ejemplo `STAGE_HM` / `DWH_HM`). Pueden convivir en la misma instancia.

Tiempo aproximado: 1 a 2 horas si hay que instalar todo; 10 minutos si ya tienes el software.

---

## 1. Software necesario

| Programa | Para qué | Notas |
|---|---|---|
| **SQL Server 2022 o 2025** (Developer, gratis) | Motor de base de datos + **Integration Services** | En el instalador marca *Servicios de Motor de base de datos* e *Integration Services* |
| **SQL Server Analysis Services** en modo **Tabular** | El cubo | Mismo instalador: marca *Analysis Services* y elige **Modo tabular**. Agrega tu usuario como administrador |
| **SQL Server Management Studio (SSMS)** | Ejecutar los scripts y ver los datos | |
| **Visual Studio 2022** (Community) | Abrir la solución | Extensiones: *SQL Server Integration Services Projects* y *Microsoft Analysis Services Projects* |
| **Power BI Desktop** (opcional) | Conectarse al cubo | |
| **Git** | Descargar el repositorio | |

Anota el **nombre de tu instancia** de SQL Server (lo ves al conectarte en SSMS), por ejemplo:
`MIPC\SQLEXPRESS`, `MIPC\DEV` o solo `MIPC` si es la instancia por defecto.
> SQL Server **Express no sirve**: no trae Integration Services ni Analysis Services. Usa **Developer**.

## 2. Descargar el proyecto

```powershell
git clone https://github.com/juanbch23/GrupoComercialAndino.git
cd GrupoComercialAndino
```
Los datos ya vienen en la carpeta `data_ventas\` (Maestros y Transacciones, 49 MB).

## 3. Adaptar el proyecto a tu PC (un solo comando)

El proyecto se construyó en la instancia `LAPTOP-IO596P6A\DEV`. Este script cambia ese nombre, la ruta de los datos y
la instancia de Analysis Services en **todos** los archivos (paquetes SSIS, conexiones, SQL y cubo):

```powershell
# desde la carpeta GrupoComercialAndino
.\herramientas\configurar_entorno.ps1 -ServidorSql "MIPC\DEV" -RutaDatos "$PWD\data_ventas" -Simular   # ver qué cambiaría
.\herramientas\configurar_entorno.ps1 -ServidorSql "MIPC\DEV" -RutaDatos "$PWD\data_ventas"            # aplicar
```
Parámetros opcionales: `-ServidorSsas "localhost\TABULAR"` (si tu Analysis Services tiene otro nombre) y
`-CuentaSsas 'NT Service\MSOLAP$TABULAR'` (cuenta del servicio de SSAS; la ves en `services.msc`).

Si PowerShell bloquea el script: `Set-ExecutionPolicy -Scope Process Bypass`.

## 4. Crear las bases de datos (SSMS)

Conéctate a tu instancia con **Autenticación de Windows** (tu usuario ya es administrador porque instalaste SQL Server)
y ejecuta, **en este orden**, abriendo cada archivo y presionando **F5**:

| # | Script | Qué crea |
|---|---|---|
| 1 | `sql\01_crear_STAGE_GCA.sql` | Base `STAGE_GCA`, esquema `GCA`, 12 tablas (una por CSV, todo texto: copia fiel) |
| 2 | `sql\02_crear_DWH_GCA.sql` | Base `DWH_GCA`: 6 dimensiones, 8 hechos, tablas de error, `DIM_AUDIT` y los procedimientos `sp_Dim...` con la limpieza de maestros |

Comprobación: en el Explorador de objetos aparecen `STAGE_GCA` (12 tablas) y `DWH_GCA` (24 tablas, 6 procedimientos).

**Usuarios y permisos:**
- **Tú (quien instaló SQL Server):** entras con Windows; SSIS y los scripts usan tu usuario (*Integrated Security*). No hay que crear nada.
- **Analysis Services:** procesa el cubo con su cuenta de servicio. El script `sql\06_vistas_cubo.sql` (paso 7) le da
  permiso de lectura sobre `DWH_GCA` (`db_datareader`).
- **Otro compañero que solo quiera consultar tu base:**
  ```sql
  USE [master]; CREATE LOGIN [EQUIPO\usuario] FROM WINDOWS WITH DEFAULT_DATABASE = [DWH_GCA];
  USE [DWH_GCA]; CREATE USER [EQUIPO\usuario] FOR LOGIN [EQUIPO\usuario];
  ALTER ROLE [db_datareader] ADD MEMBER [EQUIPO\usuario];
  ```

## 5. Cargar los datos con SSIS (Visual Studio)

1. Abre **`GCA\GCA.sln`** en Visual Studio.
2. En el *Explorador de soluciones*, proyecto **`stage_GCA`** → clic derecho en **`MasterExecuteStage.dtsx`** → **Ejecutar paquete**.
   Carga los 12 CSV al STAGE (≈ 10 s). Todas las tareas deben quedar en **verde**.
   - Si ves error de archivo no encontrado: revisa el parámetro de proyecto **`RutaDatos`** (doble clic en `Project.params`).
3. Proyecto **`DWH_GCA`** → **`MasterExecuteDWH.dtsx`** → **Ejecutar paquete** (≈ 30 s).
   Primero corre el contenedor **Dimensiones** (procedimientos `sp_Dim...`) y luego **Hechos** (8 flujos de datos).

Qué hace cada paquete de hechos (abre por ejemplo `FactVenta.dtsx` → pestaña *Flujo de datos*):
```
Origen OLE DB (consulta con limpieza) → Búsquedas DimFecha/Cliente/Vendedor/Producto/Canal/Región
   → División condicional "bad" → Columna derivada Motivo → ErrorFactVenta
                                → (salida predeterminada)  → FactVenta
```
Cada paquete sigue la plantilla del laboratorio:
`Task Prior RowCnt → Task Get AuditKey → TRUNCATE → flujo → Task Post RowCnt → Update AuditDim`.

> Alternativa sin Visual Studio (línea de comandos, la usa el autor):
> ```powershell
> $dt = "C:\Program Files\Microsoft SQL Server\170\DTS\Binn\DTExec.exe"   # 160 en SQL 2022
> & $dt /Project ".\GCA\stage_GCA\bin\Development\stage_GCA.ispac" /Package MasterExecuteStage.dtsx
> ```
> (el `.ispac` se genera al compilar el proyecto en Visual Studio: clic derecho → *Compilar*).

## 6. Validar la carga (SSMS)

| Script | Qué muestra |
|---|---|
| `sql\03_validaciones.sql` | Cuadre: archivo = STAGE, y STAGE = DWH + errores (columna *Diferencia* en **0**) |
| `sql\04_hallazgos_antes.sql` | Los datos sucios en el STAGE: venta en 0 (`VTA-00000216`), duplicados, fechas, columnas corruptas |
| `sql\05_resultado_despues.sql` | Cómo quedó cada caso en el DWH (mismo orden de bloques que el anterior) |

Resultado esperado: ventas 180,609 = 180,000 (DWH) + 609 (error); carritos 66,550 = 40,000 + 26,550;
soporte 25,636 = 25,000 + 636; llamadas 200,150 = 200,000 + 150; `DIM_AUDIT` todo en `Y`.
El detalle de cada hallazgo está en **`docs\Hallazgos_Calidad_Datos.md`**.

## 7. Cubo tabular (Analysis Services)

1. En SSMS ejecuta **`sql\06_vistas_cubo.sql`** (vistas del cubo + permiso de lectura para la cuenta de SSAS).
2. Despliega y procesa el cubo. Dos formas:
   - **Visual Studio:** proyecto `Tabular_GCA` → clic derecho → **Propiedades** → *Servidor de implementación* = tu
     instancia tabular (ej. `localhost\TABULAR`) → Aceptar → clic derecho → **Implementar**.
   - **PowerShell** (lo que usa el autor):
     ```powershell
     cd Tabular_GCA
     python gen_bim_gca.py Model.bim           # solo si cambiaste medidas en el generador
     .\deploy.ps1 -BimPath .\Model.bim         # implementa y procesa de a una tabla (≈ 15 s)
     ```
3. Comprueba en SSMS: **Conectar → Analysis Services → `localhost\TABULAR`** → base **`Tabular_GCA`**.
   Prueba una consulta DAX:
   ```powershell
   .\dax_query.ps1 -Dax 'EVALUATE ROW("Ventas", [.Ventas_Netas], "Margen", [.%Margen_Bruto], "WinRate", [.%Win_Rate])'
   ```
   Las medidas (una carpeta por indicador del caso) están descritas en **`Tabular_GCA\MEDIDAS_DAX.md`**.

**Si el procesamiento falla con "error de inicio de sesión"**: la cuenta de SSAS no tiene permiso en `DWH_GCA`.
Revisa el nombre del servicio en `services.msc` (*SQL Server Analysis Services (TABULAR)* → pestaña *Iniciar sesión*)
y vuelve a ejecutar la última parte de `06_vistas_cubo.sql` con esa cuenta.

## 8. Power BI (opcional)

Power BI Desktop → **Obtener datos → Analysis Services** → servidor `localhost\TABULAR`, base `Tabular_GCA` →
**Conectar en directo**. Las medidas aparecen agrupadas por indicador (01. Cumplimiento de cuota … 99. Calidad de datos).

## Problemas frecuentes

| Síntoma | Causa | Solución |
|---|---|---|
| SSIS: "no se puede adquirir la conexión" | Nombre de servidor distinto | Paso 3 (`configurar_entorno.ps1`) |
| SSIS: archivo no encontrado | `RutaDatos` apunta a otra carpeta | `Project.params` del proyecto `stage_GCA` |
| SQL Server deja de responder al procesar | Poca RAM libre (navegador con muchas pestañas) | Cierra programas; en SSMS: Propiedades del servidor → Memoria → máximo ≈ 25 % de la RAM |
| Tildes raras en los resultados de `sqlcmd` | Página de códigos | Usa `sqlcmd -f 65001` o SSMS |
| Visual Studio no abre los `.dtproj` | Falta la extensión de SSIS | Extensiones → *SQL Server Integration Services Projects 2022* |
