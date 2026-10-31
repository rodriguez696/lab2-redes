#!/bin/sh
while ! ip route show exact "$1" | grep -q "proto ospf"; do sleep 0.01; done
date +%s.%N > /shared/t_ruta.txt
