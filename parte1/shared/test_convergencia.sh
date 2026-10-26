#!/bin/bash
# ==============================================================================
# Script de Automatización Corregido (v7) - Prueba de Convergencia OSPF
# Soluciona: buffering de ping (stdbuf), duplicación de glob en Python y tiempos OSPF
# Obligatorio Redes - Sección 1.3
# ==============================================================================

TARGET_IP="172.16.0.9"
NUM_RUNS=5

echo "=== 1. Reiniciando escenario Kathará inicialmente ==="
kathara lrestart --noterminals

echo "=== 2. Esperando 20 segundos a que OSPF estabilice la topología inicial ==="
sleep 20

# Limpiar ejecuciones anteriores en la carpeta actual
rm -f ping_exp_*.log convergencia_exp_*.pcap 2>/dev/null

for i in $(seq 1 $NUM_RUNS); do
    LOG_FILE="ping_exp_${i}.log"
    PCAP_FILE="convergencia_exp_${i}.pcap"
    
    echo ""
    echo "=============================================================================="
    echo " REPETICIÓN $i DE $NUM_RUNS"
    echo "=============================================================================="
    
    # 1. Restablecer la interfaz en r2
    echo "-> Restableciendo interfaz eth2 (no shutdown) en r2..."
    kathara exec r2 -- sh -c "echo -e 'configure terminal\ninterface eth2\nno shutdown' | vtysh" > /dev/null 2>&1
    
    # Se aumentan a 20 segundos para asegurar que OSPF pase por Down->Init->2-Way->ExStart->Exchange->Loading->FULL
    echo "-> Esperando 20 segundos para asegurar adyacencia FULL en OSPF..."
    sleep 20

    # 2. Iniciar ping con stdbuf -oL para FORZAR el vaciado de buffer (evita archivos .log vacíos)
    echo "-> Lote de tráfico ICMP desde r1 hacia $TARGET_IP..."
    kathara exec r1 -- stdbuf -oL ping -i 0.05 -D "$TARGET_IP" > "$LOG_FILE" 2>&1 &
    PING_PID=$!
    sleep 2

    # 3. Iniciar captura tcpdump en r2
    echo "-> Iniciando captura tcpdump en r2 ($PCAP_FILE)..."
    kathara exec r2 -- tcpdump -i any -w "/shared/$PCAP_FILE" > /dev/null 2>&1 &
    sleep 1

    # 4. Generar la falla
    echo "-> Provocando falla de enlace: shutdown de eth2 en r2..."
    kathara exec r2 -- sh -c "echo -e 'configure terminal\ninterface eth2\nshutdown' | vtysh" > /dev/null 2>&1

    # 5. Se aumenta a 7 segundos para capturar la reconvergencia completa
    echo "-> Capturando reconvergencia..."
    sleep 7

    # 6. Detener procesos de esta iteración
    echo "-> Deteniendo captura y ping..."
    kathara exec r2 -- pkill -f tcpdump 2>/dev/null || true
    kill $PING_PID 2>/dev/null || true
    kathara exec r1 -- pkill -f ping 2>/dev/null || true
    sleep 1
done

echo ""
echo "=============================================================================="
echo " RESUMEN Y MÉTRICAS DE LAS $NUM_RUNS PRUEBAS"
echo "=============================================================================="

# Procesamiento en Python con glob sin duplicados
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
