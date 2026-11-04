# Node.js 26 (última versión mayor). Si tu entorno lo requiere, puedes usar la LTS: node:24-alpine
FROM node:26-alpine

ARG BUILD_ID=5230ec53
LABEL org.opencontainers.image.title="app-ecs" \
      org.opencontainers.image.version="1.0.0" \
      org.opencontainers.image.revision="${BUILD_ID}"

ENV NODE_ENV=production \
    PORT=3000

WORKDIR /app
COPY package.json ./
COPY src ./src

USER node
EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:'+(process.env.PORT||3000)+(process.env.BASE_PATH||'')+'/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

CMD ["node", "src/server.js"]
