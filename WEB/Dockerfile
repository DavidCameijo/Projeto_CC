FROM debian:12

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       nginx curl ca-certificates nodejs npm \
    && rm -rf /var/lib/apt/lists/* \

WORKDIR /opt/app
COPY app/ . 

RUN npm install --omit=dev

COPY app/server.js ./

EXPOSE 3000
CMD ["npm", "start"]