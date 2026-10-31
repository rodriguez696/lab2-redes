#!/bin/bash
# Parte 1.4 - Tiempo desde que se habilitan las adyacencias de r8 hasta que r1
# instala una ruta OSPF hacia la nueva LAN. Una sola medición.
# Este script vive en shared/ pero se ejecuta desde el directorio del lab:
#   ./shared/nueva_ruta_r1_to_rclA_v2.sh
# Requiere: lab levantado, r8 con interfaces en shutdown y OSPF convergido.
# (kathara rechaza '-c': los comandos con -c van en auxiliares dentro de shared/)

TARGET_SUBNET="203.0.113.12/30"
DIR="$(dirname "$0")"      # carpeta shared (donde está este script)

rm -f "$DIR/t_ini.txt" "$DIR/t_ruta.txt" "$DIR/ospf_r8.pcap"

# Auxiliar en r1: espera (polling 10 ms) a que el kernel tenga la ruta OSPF y guarda la hora
cat << 'EOS' > "$DIR/h_wait_route.sh"
#!/bin/sh
while ! ip route show exact "$1" | grep -q "proto ospf"; do sleep 0.01; done
date +%s.%N > /shared/t_ruta.txt
EOS

# Auxiliar en r8: guarda la hora y habilita las interfaces
cat << 'EOS' > "$DIR/h_if.sh"
#!/bin/sh
date +%s.%N > /shared/t_ini.txt
vtysh -c "configure terminal" \
      -c "interface eth0" -c "no shutdown" -c "exit" \
      -c "interface eth1" -c "no shutdown" -c "exit" \
      -c "interface eth2" -c "no shutdown"
EOS
chmod +x "$DIR"/h_*.sh

# Captura OSPF en r8 y espera de la ruta en r1 (en segundo plano)
kathara exec r8 -- tcpdump -U -i any -w /shared/ospf_r8.pcap ip proto 89 > /dev/null 2>&1 &
kathara exec r1 -- timeout 120 sh /shared/h_wait_route.sh "$TARGET_SUBNET" > /dev/null 2>&1 &
WAIT_PID=$!
sleep 3

# Habilitar interfaces de r8
kathara exec r8 -- sh /shared/h_if.sh > /dev/null 2>&1

wait $WAIT_PID
sleep 2
kathara exec r8 -- pkill tcpdump 2>/dev/null || true

if [ ! -s "$DIR/t_ruta.txt" ]; then
    echo "La ruta no apareció en r1 en 120 s: revisar adyacencias."
    exit 1
fi

T_INI=$(cat "$DIR/t_ini.txt")
T_FIN=$(cat "$DIR/t_ruta.txt")

RES=$(python3 -c "print(f'{$T_FIN - $T_INI:.4f}')")

echo "Tiempo en que r1 instala ruta hacia la nueva LAN ($TARGET_SUBNET): $RES seg"
