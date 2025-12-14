FROM debian:12

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       nginx curl ca-certificates nodejs npm jq  \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/app
COPY app/ . 

RUN npm install --omit=dev

COPY app/server.js ./
COPY config-integrity.sh /usr/local/bin/config-integrity.sh
RUN chmod +x /usr/local/bin/config-integrity.sh

EXPOSE 3000

# Create entrypoint script with integrity check
RUN echo '#!/bin/bash' > /entrypoint.sh && \
    echo 'set -e' >> /entrypoint.sh && \
    echo 'echo "[WEB] Starting web service..."' >> /entrypoint.sh && \
    echo 'if [ -f /usr/local/bin/config-integrity.sh ]; then' >> /entrypoint.sh && \
    echo '  /usr/local/bin/config-integrity.sh verify' >> /entrypoint.sh && \
    echo 'fi' >> /entrypoint.sh && \
    echo 'echo "[WEB] Starting Node.js application..."' >> /entrypoint.sh && \
    echo 'exec npm start' >> /entrypoint.sh && \
    chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]