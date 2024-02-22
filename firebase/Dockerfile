FROM node:20.11-slim

RUN <<EOF
apt-get -y update
apt-get -y install git
npm install -g firebase-tools
EOF

EXPOSE 9005

WORKDIR /app
