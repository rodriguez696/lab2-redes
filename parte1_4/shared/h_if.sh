#!/bin/sh
date +%s.%N > /shared/t_ini.txt
vtysh -c "configure terminal" \
      -c "interface eth0" -c "no shutdown" -c "exit" \
      -c "interface eth1" -c "no shutdown" -c "exit" \
      -c "interface eth2" -c "no shutdown"
