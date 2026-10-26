#!/bin/bash
# ==============================================================================
# Script de Automatización Corregido (v10) - Prueba de Convergencia OSPF
# Solución definitiva al problema de logs no creados:
# 1. Usa un script auxiliar (do_ping.sh) para evitar el uso del flag '-c' (error de PyInstaller).
# 2. Evita la tubería (pipe) en segundo plano que cerraba stdin y mataba al ping prematuramente.
# Obligatorio Redes - Sección 1.3
# ==============================================================================

TARGET_IP="172.16.0.9"
NUM_RUNS=5

# 1. Crear un pequeño script auxiliar en la carpeta actual (/shared)
cat << 'PING_SCRIPT' > do_ping.sh
#!/bin/sh
ping -i 0.05 -D "$1" > "$2" 2>&1
PING_SCRIPT
chmod +x do_ping.sh

echo "=== 1. Reiniciando escenario Kathará inicialmente ==="
kathara lrestart --noterminals

echo "=== 2. Esperando 20 segundos a que OSPF estabilice la topología inicial ==="
sleep 20

# Limpiar ejecuciones anteriores en la carpeta compartida
rm -f ping_exp_*.log convergencia_exp_*.pcap 2>/dev/null

for i in $(seq 1 $NUM_RUNS); do
    LOG_FILE="ping_exp_${i}.log"
    PCAP_FILE="convergencia_exp_${i}.pcap"
    
    echo ""
    echo "=============================================================================="
    echo " REPETICIÓN $i DE $NUM_RUNS"
    echo "=============================================================================="
    
    # Restablecer la interfaz en r2 mediante vtysh por stdin (sincrónico)
    echo "-> Restableciendo interfaz eth2 (no shutdown) en r2..."
    echo -e "configure terminal\ninterface eth2\nno shutdown" | kathara exec r2 -- vtysh > /dev/null 2>&1
    
    # 20 segundos para asegurar adyacencia OSPF FULL
    echo "-> Esperando 20 segundos para asegurar adyacencia FULL en OSPF..."
    sleep 20

    # Iniciar ping ejecutando el script auxiliar sin pipe ni -c
    echo "-> Lote de tráfico ICMP desde r1 hacia $TARGET_IP (log: $LOG_FILE)..."
    kathara exec r1 -- sh /shared/do_ping.sh "$TARGET_IP" "/shared/$LOG_FILE" > /dev/null 2>&1 &
    sleep 2

    # Iniciar captura tcpdump en r2
    echo "-> Iniciando captura tcpdump en r2 ($PCAP_FILE)..."
    kathara exec r2 -- tcpdump -i any -w "/shared/$PCAP_FILE" > /dev/null 2>&1 &
    sleep 1

    # Generar la falla mediante vtysh
    echo "-> Provocando falla de enlace: shutdown de eth2 en r2..."
    echo -e "configure terminal\ninterface eth2\nshutdown" | kathara exec r2 -- vtysh > /dev/null 2>&1

    # Captura extendida a 7 segundos para registrar reconvergencia completa
    echo "-> Capturando reconvergencia..."
    sleep 7

    # Detener procesos dentro de los contenedores
    echo "-> Deteniendo captura y ping..."
    kathara exec r2 -- pkill -f tcpdump 2>/dev/null || true
    kathara exec r1 -- pkill -f ping 2>/dev/null || true
    sleep 1
done

echo ""
echo "=============================================================================="
echo " RESUMEN Y MÉTRICAS DE LAS $NUM_RUNS PRUEBAS"
echo "=============================================================================="

# Procesamiento en Python leyendo los logs creados en la carpeta actual
python3 << 'EOF'
import re
import glob
import os

logs = sorted(glob.glob("ping_exp_*.log"))
tiempos = []

header_fmt = "| {:<10} | {:<18} | {:<18} | {:<18} |"
row_fmt    = "| {:<10} | {:<18.6f} | {:<18.6f} | {:<18.4f} |"

print(header_fmt.format("Muestra", "T_falla (s)", "T_recup (s)", "Tiempo Recup (s)"))
print("|" + "-"*12 + "|" + "-"*20 + "|" + "-"*20 + "|" + "-"*20 + "|")

for idx, log_path in enumerate(logs, 1):
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
