#!/bin/bash
# ==============================================================================
# Script de Automatización Corregido (v9) - Prueba de Convergencia OSPF
# Solución al error PyInstaller: Eliminación total de argumentos '-c'
# Redirección directa dentro del contenedor en /shared/
# Obligatorio Redes - Sección 1.3
# ==============================================================================

TARGET_IP="172.16.0.9"
NUM_RUNS=5

echo "=== 1. Reiniciando escenario Kathará inicialmente ==="
kathara lrestart --noterminals

echo "=== 2. Esperando 20 segundos a que OSPF estabilice la topología inicial ==="
sleep 20

# Limpiar ejecuciones anteriores en la carpeta compartida
rm -f ping_exp_*.log convergencia_exp_*.pcap /shared/ping_exp_*.log /shared/convergencia_exp_*.pcap 2>/dev/null

for i in $(seq 1 $NUM_RUNS); do
    LOG_FILE="ping_exp_${i}.log"
    PCAP_FILE="convergencia_exp_${i}.pcap"
    
    echo ""
    echo "=============================================================================="
    echo " REPETICIÓN $i DE $NUM_RUNS"
    echo "=============================================================================="
    
    # 1. Restablecer la interfaz en r2 mediante pipe a vtysh (sin usar -c)
    echo "-> Restableciendo interfaz eth2 (no shutdown) en r2..."
    echo -e "configure terminal\ninterface eth2\nno shutdown" | kathara exec r2 -- vtysh > /dev/null 2>&1
    
    # 20 segundos para asegurar adyacencia OSPF FULL
    echo "-> Esperando 20 segundos para asegurar adyacencia FULL en OSPF..."
    sleep 20

    # 2. Iniciar ping enviando la orden por stdin a 'sh' (sin usar -c)
    echo "-> Lote de tráfico ICMP desde r1 hacia $TARGET_IP (log en /shared/$LOG_FILE)..."
    echo "exec ping -i 0.05 -D $TARGET_IP > /shared/$LOG_FILE 2>&1" | kathara exec r1 -- sh &
    sleep 2

    # 3. Iniciar captura tcpdump en r2
    echo "-> Iniciando captura tcpdump en r2 (/shared/$PCAP_FILE)..."
    kathara exec r2 -- tcpdump -i any -w "/shared/$PCAP_FILE" > /dev/null 2>&1 &
    sleep 1

    # 4. Generar la falla mediante pipe a vtysh (sin usar -c)
    echo "-> Provocando falla de enlace: shutdown de eth2 en r2..."
    echo -e "configure terminal\ninterface eth2\nshutdown" | kathara exec r2 -- vtysh > /dev/null 2>&1

    # 5. Captura extendida a 7 segundos para registrar reconvergencia completa
    echo "-> Capturando reconvergencia..."
    sleep 7

    # 6. Detener procesos dentro de los contenedores
    echo "-> Deteniendo captura y ping..."
    kathara exec r2 -- pkill -f tcpdump 2>/dev/null || true
    kathara exec r1 -- pkill -f ping 2>/dev/null || true
    sleep 1
done

echo ""
echo "=============================================================================="
echo " RESUMEN Y MÉTRICAS DE LAS $NUM_RUNS PRUEBAS"
echo "=============================================================================="

# Procesamiento en Python leyendo directamente los logs generados en /shared
python3 << 'EOF'
import re
import glob
import os

# Buscar archivos en la carpeta actual o en /shared
raw_logs = glob.glob("ping_exp_*.log") + glob.glob("/shared/ping_exp_*.log")
# Obtener rutas absolutas únicas
unique_logs = sorted(list(set(os.path.realpath(p) for p in raw_logs if os.path.exists(p))))

tiempos = []

header_fmt = "| {:<10} | {:<18} | {:<18} | {:<18} |"
row_fmt    = "| {:<10} | {:<18.6f} | {:<18.6f} | {:<18.4f} |"

print(header_fmt.format("Muestra", "T_falla (s)", "T_recup (s)", "Tiempo Recup (s)"))
print("|" + "-"*12 + "|" + "-"*20 + "|" + "-"*20 + "|" + "-"*20 + "|")

for idx, log_path in enumerate(unique_logs, 1):
    try:
        if os.path.getsize(log_path) == 0:
            print(f"| {'Prueba ' + str(idx):<10} | {'Log vacío':<18} | {'Log vacío':<18} | {'N/A':<18} |")
            continue
            
        with open(log_path) as f:
            last_seq, last_time = None, None
            corte_encontrado = False
            for line in f:
                t_m = re.search(r"\\[([\d\.]+)\\]", line)
                s_m = re.search(r"icmp_seq=(\d+)", line)
                if s_m and t_m:
                    t, s = float(t_m.group(1)), int(s_m.group(1))
                    if last_seq is not None and s > last_seq + 1:
                        duracion = t - last_time
                        tiempos.append(duracion)
                        print(row_fmt.format(f"Prueba {idx}", last_time, t, duracion))
                        corte_encontrado = True
                        break
                    last_seq, last_time = s, t
            if not corte_encontrado:
                print(f"| {'Prueba ' + str(idx):<10} | {'N/A (0% pérdida)':<18} | {'N/A (0% pérdida)':<18} | {'0.0000 (instant.)':<18} |")
                tiempos.append(0.0)
    except Exception as e:
        print(f"| {'Prueba ' + str(idx):<10} | {'Error archivo':<18} | {'Error archivo':<18} | {'N/A':<18} |")

if tiempos:
    t_min = min(tiempos)
    t_max = max(tiempos)
    t_prom = sum(tiempos) / len(tiempos)
    print("\n" + "="*72)
    print(f" MÍNIMO   : {t_min:.4f} s ({t_min*1000:.1f} ms)")
    print(f" MÁXIMO   : {t_max:.4f} s ({t_max*1000:.1f} ms)")
    print(f" PROMEDIO : {t_prom:.4f} s ({t_prom*1000:.1f} ms)")
    print("="*72)
EOF
