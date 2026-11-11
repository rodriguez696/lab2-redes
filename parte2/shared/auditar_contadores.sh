echo "counter_read paquetes_puerto 0" | simple_switch_CLI > shared/paquetes_puerto_0.txt
echo "counter_read paquetes_puerto 1" | simple_switch_CLI > shared/paquetes_puerto_1.txt
echo "counter_read paquetes_puerto 2" | simple_switch_CLI > shared/paquetes_puerto_2.txt
echo "counter_read paquetes_puerto 3" | simple_switch_CLI > shared/paquetes_puerto_3.txt
echo "counter_read paquetes_descartados__switch_port 0" | simple_switch_CLI > shared/paquetes_descartados__switch_port_0.txt
echo "counter_read paquetes_descartados__invalid_traffic 0" | simple_switch_CLI > shared/paquetes_descartados__invalid_traffic_0.txt

