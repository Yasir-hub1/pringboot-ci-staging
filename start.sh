#!/bin/bash

# Iniciar SSH
service ssh start

# Mantener el contenedor activo
tail -f /dev/null