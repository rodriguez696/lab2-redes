# Parte 1.3 – Convergencia OSPF ante falla de enlace (Kathará + FRR)

Automatización del experimento de la sección 1.3 del Obligatorio 2 (Redes de Computadoras, 2026):
medir cuánto tiempo pierde conectividad un flujo `ping` cuando se deshabilita el enlace **r2–r4**
del backbone de RíoNet, repitiendo el experimento 5 veces y reportando mínimo, máximo y promedio.

> Este documento sirve tanto para una persona que no conoce el código como para dar contexto
> a una herramienta de IA. Describe qué hace cada pieza, por qué se hizo así y qué errores ya se resolvieron.

## 1. Contexto del escenario

- Laboratorio Kathará en `~/lab2-redes/parte1/` (archivo `lab.conf`, imagen `kathara/frr`).
- Backbone de 6 routers (r1–r6) con OSPF; `rInt` representa Internet. Enlaces punto a punto /30 en `172.16.0.0/26`.
- Enlaces relevantes para la prueba (nombre de dominio de colisión → interfaces → prefijo):

| Enlace | Interfaces | Prefijo |
|---|---|---|
| R1_R2 | r1 `eth1` (172.16.0.17) – r2 `eth0` (172.16.0.18) | 172.16.0.16/30 |
| R2_R4 | r2 `eth2` (172.16.0.37) – r4 `eth0` (172.16.0.38) | 172.16.0.36/30 |
| R4_R6 | r4 `eth2` (172.16.0.10) – r6 `eth1` (172.16.0.9) | 172.16.0.8/30 |

- **Flujo de prueba:** `ping` desde **r1** hacia **172.16.0.9** (interfaz de r6 hacia r4).
  Camino en estado estable: `r1 → r2 → r4 → r6` (3 saltos, respuestas con `ttl=62`), único next-hop en r1 (sin ECMP para este destino).
- **Falla provocada:** `shutdown` de `eth2` en **r2** (el enlace R2_R4) mediante `vtysh`.

## 2. Archivos

| Archivo | Descripción |
|---|---|
| `test_convergencia.sh` | Script principal. Ejecutar desde el directorio del laboratorio (donde está `lab.conf`). |
| `shared/` | Carpeta compartida host ↔ contenedores (dentro de los contenedores es `/shared`). Aquí se generan todos los resultados. |

Scripts auxiliares que `test_convergencia.sh` genera en `shared/` (se ejecutan **dentro** de los contenedores):

| Auxiliar | Función |
|---|---|
| `do_ping.sh` | `ping -i <intervalo> -D -c <cantidad> -W 1 <destino>` con salida a un log. |
| `h_link.sh` | `up`/`down` de una interfaz vía `vtysh`; opcionalmente guarda el timestamp (`date +%s.%N`) justo antes. |
| `h_snap.sh` | Guarda `ip route` e `ip route get <destino>` (tabla de forwarding). |
| `h_path.sh` | Verificación previa del camino (`ip route get`, `show ip route`, `traceroute`). |

## 3. Cómo ejecutar

Siempre desde el directorio del laboratorio `~/lab2-redes/parte1` (el script usa rutas relativas a `shared/`):

```bash
cd ~/lab2-redes/parte1
chmod +x test_convergencia.sh
./test_convergencia.sh        # ~6 min; hace kathara lrestart al inicio
```

Para guardar los datos del experimento (opcional), también desde `~/lab2-redes/parte1`:

```bash
cd shared && tar -czf "../5_exps_$(date +%Y%m%d_%H%M%S).tar.gz" conv_r2_*.pcap conv_r4_*.pcap ping_exp_*.log rutas_antes_*.txt rutas_despues_*.txt t_falla_*.txt; cd ..
```

Esto genera `5_exps_<fecha_hora>.tar.gz` en `~/lab2-redes/parte1/` (fuera de `shared/`) con 30 archivos: 5 de cada tipo
(`conv_r2`, `conv_r4`, `ping_exp`, `rutas_antes`, `rutas_despues`, `t_falla`). Se puede comprobar con `tar -tzf 5_exps_*.tar.gz`.

Parámetros editables al inicio de `test_convergencia.sh`: `TARGET_IP`, `NUM_RUNS`, `PRE_FALLA`, `POST_FALLA`, `INTERVALO` (0.01 s).
El script **borra** los resultados anteriores (`ping_exp_*`, `conv_*`, `t_falla_*`, `rutas_*`) al empezar: empaquetar antes de volver a correrlo.

## 4. Qué hace el script (flujo)

1. Crea los auxiliares en `shared/` y limpia resultados anteriores.
2. `kathara lrestart --noterminals` **una sola vez** y espera **60 s** a que OSPF converja.
3. Muestra el camino r1 → destino (verificación manual: debe cruzar r2–r4).
4. Repite `NUM_RUNS` (5) veces:
   1. `no shutdown` de `eth2` en r2 y espera 35 s (vuelve al camino original).
   2. Guarda tabla de rutas de r1 **antes** (`rutas_antes_N.txt`).
   3. Lanza el ping en r1 en segundo plano (1500 paquetes a 10 ms ≈ 15 s).
   4. A los 2 s inicia `tcpdump -i any` en **r2 y r4** (`conv_r2_N.pcap`, `conv_r4_N.pcap`).
   5. 2 s después hace el `shutdown` de `eth2` en r2 y guarda el instante exacto (`t_falla_N.txt`, tomado dentro de r2 con el mismo reloj que usa `ping -D`).
   6. Confirma con `ip -o link show eth2` que quedó `state DOWN`.
   7. Guarda tabla de rutas **después** (`rutas_despues_N.txt`), espera, detiene `tcpdump` y espera a que termine el ping.
5. Restaura la interfaz y un bloque Python calcula la tabla resumen.

## 5. Cómo se calcula el resultado

El log del ping (`-D` agrega timestamp epoch) se analiza así:

- Se consideran solo líneas con `bytes from` (respuestas exitosas).
- **Corte** = primer salto en `icmp_seq` posterior al instante de falla. `Sin conect. = t(primer OK después) − t(último OK antes)`.
- `Falla→OK = t(primer OK después) − T_falla` (sobreestima levemente: el timestamp se toma antes de que arranque `vtysh`).
- `Perdidos` = paquetes del hueco; `ICMP err` = líneas `From … icmp_seq=…` (típicamente `Redirect Host`).
- Si una corrida no pierde paquetes se informa como "sin pérdida detectable (< 10 ms)" y no entra en mín/máx/promedio.

## 6. Resultados obtenidos (dos corridas de 5 repeticiones)

| | Corrida 1 | Corrida 2 |
|---|---|---|
| Sin conectividad: mín / máx / prom | 0.0206 / 0.0395 / 0.0274 s | 0.0202 / 0.0256 / 0.0221 s |
| Paquetes perdidos por prueba | 1 | 1 |
| ICMP Redirect por prueba | 1 | 1 |

Interpretación:

- El corte percibido es de ~20 ms (1 paquete perdido a 10 ms). Los routers adyacentes (r2, r4) detectan la caída al instante y recalculan localmente.
- El ICMP **Redirect Host** que envía r2 apuntando a r1 (`New nexthop: 172.16.0.17`) es evidencia de un **microloop transitorio** r1↔r2 durante la reconvergencia.
- La dispersión (p. ej. 39.5 ms en una prueba) es **ruido del entorno** (contenedores + `tcpdump` compartiendo la CPU de una VM), no del protocolo: se verificó con `awk` que el mismo log tiene saltos de 50–100 ms fuera del evento de falla.
- Pregunta 1.3: el ping **no** mide exactamente la convergencia de OSPF; mide el corte visto por un flujo y está limitado por el intervalo del ping, por qué router detecta la falla, el retardo de SPF y la inundación de LSAs.

## 7. Problemas encontrados y decisiones (importante si se modifica el script)

| Problema | Causa | Solución |
|---|---|---|
| `Error, the program tried to call itself with '-c' argument` | El binario de `kathara` rechaza cualquier `-c` en su línea de comandos (también `sh -c`, `vtysh -c`). | Todo lo que necesita `-c` vive en scripts de `shared/` y se invoca como `kathara exec rX -- sh /shared/h_*.sh …`. |
| `echo … \| kathara exec r2 -- vtysh` no hacía nada | `kathara exec` no reenvía stdin. | Usar `vtysh -c` **dentro** de un script auxiliar. |
| Logs sin pérdida con la falla aplicada | Con ping cada 50 ms el corte (~20 ms) puede caer entre dos paquetes. | Intervalo de 10 ms. |
| `ping_exp_2.log` terminaba al recibir el Redirect | `ping -w` (deadline) termina al primer error ICMP. | Usar `-c <cantidad>` en lugar de `-w`. |
| Verificaciones inconsistentes tras `lrestart` | OSPF no había convergido. | Espera inicial de 60 s. |
| `tar` "Cannot stat" con comodines | La shell expande `*` en la carpeta actual, no en la de `-C`. | `cd shared && tar …` (ver sección 3). |

## 8. Limitaciones conocidas

- Resolución de 10 ms; con 5 muestras las diferencias de ~15 ms están dentro del ruido.
- `Falla→OK` incluye la latencia de lanzar `vtysh`; `Sin conect.` es la métrica más fiable.
- Se mide un único flujo ICMP en un solo sentido de ida (las respuestas siguen su propio camino).
- Es una falla "limpia" (`shutdown`): la detección es inmediata. Una falla silenciosa (p. ej. `tc netem loss 100%`) dependería del *dead interval* de OSPF y daría tiempos mucho mayores.

## 9. Nota sobre la entrega

La letra exige declarar en el informe todo uso de herramientas de IA (herramienta utilizada y para qué se empleó) y poder justificar cada parte del código en la defensa.
