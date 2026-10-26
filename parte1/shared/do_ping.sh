#!/bin/sh
ping -i 0.05 -D "$1" > "$2" 2>&1
