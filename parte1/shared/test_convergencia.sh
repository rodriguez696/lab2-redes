#!/bin/bash
# ==============================================================================
# Prueba de Convergencia OSPF (v17) - Obligatorio Redes - Sección 1.3
# Ejecutar desde el directorio del laboratorio (donde está lab.conf).
# kathara rechaza '-c' en su línea de comandos: todo lo que lo necesita vive en
# scripts auxiliares dentro de shared/.
# v17: ping con -c (no -w, que corta el ping al primer ICMP de error, p.ej. un
#      Redirect), intervalo de 10 ms, y manejo de corridas sin pérdida detectable.
# ==============================================================================

TARGET_IP="172.16.0.9"
NUM_RUNS=5
PRE_FALLA=4
POST_FALLA=8
INTERVALO=0.01
PING_COUNT=$(( (PRE_FALLA + POST_FALLA + 3) * 100 ))   # 100 pkts/s * segundos

mkdir -p shared
rm -f shared/ping_exp_*.log shared/conv_*.pcap shared/t_falla_*.txt shared/rutas_*.txt 2>/dev/null

cat << 'EOS' > shared/do_ping.sh
#!/bin/sh
# $1 destino, $2 log, $3 cantidad de paquetes, $4 intervalo (s)
ping -i "$4" -D -c "$3" -W 1 "$1" > "$2" 2>&1
EOS

cat << 'EOS' > shared/h_link.sh
#!/bin/sh
# $1 up|down, $2 interfaz, $3 archivo donde guardar timestamp (opcional)
[ -n "$3" ] && date +%s.%N > "$3"
if [ "$1" = "down" ]; then CMD="shutdown"; else CMD="no shutdown"; fi
vtysh -c "configure terminal" -c "interface $2" -c "$CMD"
EOS

cat << 'EOS' > shared/h_snap.sh
#!/bin/sh
# $1 destino, $2 archivo de salida
{ ip route; echo; ip route get "$1"; } > "$2" 2>&1
EOS

cat << 'EOS' > shared/h_path.sh
#!/bin/sh
# $1 destino
ip route get "$1"
vtysh -c "show ip route $1"
traceroute -n "$1" 2>/dev/null || true
EOS
chmod +x shared/*.sh

echo "=== 1. Reiniciando escenario ==="
kathara lrestart --noterminals

echo "=== 2. Esperando 60 s por convergencia OSPF inicial ==="
sleep 60

echo "=== Verificación previa del camino r1 -> $TARGET_IP (debe cruzar r2-r4) ==="
kathara exec r1 -- sh /shared/h_path.sh "$TARGET_IP"

for i in $(seq 1 $NUM_RUNS); do
    LOG="ping_exp_${i}.log"
    echo ""
    echo "=============== REPETICIÓN $i DE $NUM_RUNS ==============="

    echo "-> Restaurando eth2 en r2..."
    kathara exec r2 -- sh /shared/h_link.sh up eth2 > /dev/null 2>&1
    echo "-> Esperando 35 s para reconvergencia al camino original..."
    sleep 35

    kathara exec r1 -- sh /shared/h_snap.sh "$TARGET_IP" "/shared/rutas_antes_${i}.txt" > /dev/null 2>&1

    echo "-> Iniciando ping en r1 ($LOG)..."
    kathara exec r1 -- sh /shared/do_ping.sh "$TARGET_IP" "/shared/$LOG" "$PING_COUNT" "$INTERVALO" > /dev/null 2>&1 &
    PING_PID=$!
    sleep 2

    echo "-> Iniciando tcpdump en r2 y r4..."
    kathara exec r2 -- tcpdump -U -i any -w "/shared/conv_r2_${i}.pcap" > /dev/null 2>&1 &
    kathara exec r4 -- tcpdump -U -i any -w "/shared/conv_r4_${i}.pcap" > /dev/null 2>&1 &
    sleep $((PRE_FALLA - 2))

    echo "-> Provocando falla (shutdown eth2 en r2)..."
    kathara exec r2 -- sh /shared/h_link.sh down eth2 "/shared/t_falla_${i}.txt" > /dev/null 2>&1

    ESTADO=$(kathara exec r2 -- ip -o link show eth2 2>/dev/null)
    if echo "$ESTADO" | grep -q "state DOWN"; then
        echo "   eth2 DOWN confirmado."
    else
        echo "   !! AVISO: eth2 NO quedó DOWN: $ESTADO"
    fi

    sleep 1
    kathara exec r1 -- sh /shared/h_snap.sh "$TARGET_IP" "/shared/rutas_despues_${i}.txt" > /dev/null 2>&1
    sleep $((POST_FALLA - 1))

    echo "-> Deteniendo capturas..."
    kathara exec r2 -- pkill tcpdump 2>/dev/null || true
    kathara exec r4 -- pkill tcpdump 2>/dev/null || true
    wait $PING_PID 2>/dev/null     # el ping termina solo al enviar PING_COUNT paquetes
    sleep 1
done

kathara exec r2 -- sh /shared/h_link.sh up eth2 > /dev/null 2>&1

echo ""
echo "=============== RESUMEN ==============="
NUM_RUNS=$NUM_RUNS INTERVALO=$INTERVALO python3 << 'EOF'
import re, os

INTERVALO = float(os.environ["INTERVALO"])

def leer(path):
    ok, errs = [], 0
    with open(path) as f:
        for line in f:
            t = re.search(r"\[([\d.]+)\]", line)
            s = re.search(r"icmp_seq=(\d+)", line)
            if "bytes from" in line and t and s:
                ok.append((float(t.group(1)), int(s.group(1))))
            elif re.search(r"^\[[\d.]+\] From \S+ icmp_seq=", line):
                errs += 1          # Redirect Host, TTL exceeded, Unreachable, ...
    return ok, errs

outages, desde_falla, sin_perdida = [], [], 0
print(f"| {'Prueba':<6} | {'T_falla':<17} | {'Último OK':<17} | {'Primer OK nuevo':<17} | {'Sin conect.(s)':<14} | {'Falla->OK (s)':<13} | {'Perdidos':<8} | {'ICMP err':<8} |")
print("|" + "-"*8 + ("|" + "-"*19)*3 + "|" + "-"*16 + "|" + "-"*15 + "|" + "-"*10 + "|" + "-"*10 + "|")

for i in range(1, int(os.environ["NUM_RUNS"]) + 1):
    try:
        ok, errs = leer(f"shared/ping_exp_{i}.log")
        t_falla = float(open(f"shared/t_falla_{i}.txt").read().strip())
    except Exception as e:
        print(f"| Prueba {i}: error leyendo archivos ({e})")
        continue
    gap = None
    for (t0, s0), (t1, s1) in zip(ok, ok[1:]):
        if s1 > s0 + 1 and t1 >= t_falla:
            gap = (t0, t1, s1 - s0 - 1)
            break
    if gap is None:
        sin_perdida += 1
        print(f"| {i:<6} | {t_falla:<17.6f} | sin pérdida detectable (corte < {INTERVALO*1000:.0f} ms, resolución del ping)        | {'-':<8} | {errs:<8} |")
        continue
    t0, t1, perd = gap
    outages.append(t1 - t0)
    desde_falla.append(t1 - t_falla)
    print(f"| {i:<6} | {t_falla:<17.6f} | {t0:<17.6f} | {t1:<17.6f} | {t1-t0:<14.4f} | {t1-t_falla:<13.4f} | {perd:<8} | {errs:<8} |")

def stats(nombre, v):
    if v:
        print(f" {nombre}: min={min(v):.4f}s  max={max(v):.4f}s  prom={sum(v)/len(v):.4f}s  (n={len(v)})")

print()
stats("Periodo sin conectividad (ping)", outages)
stats("Falla -> primer ping exitoso   ", desde_falla)
if sin_perdida:
    print(f" Corridas sin pérdida detectable (corte < {INTERVALO*1000:.0f} ms): {sin_perdida}  (no entran en las estadísticas)")
EOF