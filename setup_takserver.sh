#!/bin/bash

set -e

echo "📦 Preparando estructura del proyecto..."
mkdir -p takserver-docker/{certs,data}

cd takserver-docker

# Verifica si el .deb ya está presente
if [ ! -f takserver_5.2-RELEASE56_all.deb ]; then
    echo "⚠️  Archivo takserver_5.2-RELEASE56_all.deb no encontrado."
    echo "🔁 Por favor copia el archivo al directorio actual antes de continuar."
    exit 1
fi

# Crear Dockerfile si no existe
if [ ! -f Dockerfile ]; then
    echo "📝 Creando Dockerfile..."
    cat <<EOF > Dockerfile
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y openjdk-17-jre postgresql postgresql-contrib \
    libpq-dev wget unzip gnupg2 ca-certificates && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

COPY takserver_5.2-RELEASE56_all.deb /opt/tak/
WORKDIR /opt/tak

RUN apt update && apt install -y ./takserver_5.2-RELEASE56_all.deb

EXPOSE 8443 8444 8446

CMD ["/opt/tak/TakServer/takserver.sh"]
EOF
fi

# Crear docker-compose.yml si no existe
if [ ! -f docker-compose.yml ]; then
    echo "📝 Creando docker-compose.yml..."
    cat <<EOF > docker-compose.yml
version: '3.8'

services:
  takserver:
    build: .
    container_name: takserver
    ports:
      - "8443:8443"
      - "8444:8444"
      - "8446:8446"
    volumes:
      - ./data:/opt/tak/data
      - ./certs:/opt/tak/certs
    restart: unless-stopped
EOF
fi

# Generar CA y certificados
echo "🔑 Generando la Autoridad Certificadora (CA)..."
openssl genpkey -algorithm RSA -out /opt/tak/certs/ca.key -pkeyopt rsa_keygen_bits:2048
openssl req -key /opt/tak/certs/ca.key -new -x509 -out /opt/tak/certs/ca.crt -subj "/CN=TAKServer CA"

echo "🔑 Generando certificado para el servidor..."
openssl genpkey -algorithm RSA -out /opt/tak/certs/takserver.key -pkeyopt rsa_keygen_bits:2048
openssl req -key /opt/tak/certs/takserver.key -new -out /opt/tak/certs/takserver.csr -subj "/CN=takserver"
openssl x509 -req -in /opt/tak/certs/takserver.csr -CA /opt/tak/certs/ca.crt -CAkey /opt/tak/certs/ca.key -CAcreateserial -out /opt/tak/certs/takserver.crt -days 365

echo "🔑 Generando certificado para 'webadmin' (administrador)..."
openssl genpkey -algorithm RSA -out /opt/tak/certs/webadmin.key -pkeyopt rsa_keygen_bits:2048
openssl req -key /opt/tak/certs/webadmin.key -new -out /opt/tak/certs/webadmin.csr -subj "/CN=webadmin"
openssl x509 -req -in /opt/tak/certs/webadmin.csr -CA /opt/tak/certs/ca.crt -CAkey /opt/tak/certs/ca.key -CAcreateserial -out /opt/tak/certs/webadmin.crt -days 365

echo "🔑 Generando certificado para 'alfa1' (usuario)..."
openssl genpkey -algorithm RSA -out /opt/tak/certs/alfa1.key -pkeyopt rsa_keygen_bits:2048
openssl req -key /opt/tak/certs/alfa1.key -new -out /opt/tak/certs/alfa1.csr -subj "/CN=alfa1"
openssl x509 -req -in /opt/tak/certs/alfa1.csr -CA /opt/tak/certs/ca.crt -CAkey /opt/tak/certs/ca.key -CAcreateserial -out /opt/tak/certs/alfa1.crt -days 365

# Configurar permisos de administrador y usuario
echo "🛠️ Registrando certificados en TAKServer..."
sudo java -jar /opt/tak/utils/UserManager.jar certmod -A -c /opt/tak/certs/webadmin.crt
sudo java -jar /opt/tak/utils/UserManager.jar certmod -c /opt/tak/certs/alfa1.crt

# Construir la imagen Docker
echo "🔧 Construyendo imagen Docker..."
docker-compose build

# Levantar el contenedor
echo "🚀 Levantando TAKServer..."
docker-compose up -d

echo "✅ TAKServer desplegado con éxito en contenedor Docker."
