FROM node:24.22.2-alpine3.23 AS deps
WORKDIR /app
COPY app/package*.json ./
RUN npm ci --omit=dev --ignore-scripts

FROM node:24.22.2-alpine3.23

ARG VERSION=dev
ARG REVISION=unknown
LABEL org.opencontainers.image.title="devops-task-app" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${REVISION}" \
      org.opencontainers.image.source="https://github.com/kaisarmonir/devops-assessment"

# npm, yarn and corepack are not needed at runtime,
# removing them keeps their dependencies out of the vulnerability scan
RUN rm -rf /usr/local/lib/node_modules /opt/yarn* \
           /usr/local/bin/np[mx] /usr/local/bin/yarn* /usr/local/bin/corepack

ENV NODE_ENV=production PORT=8080 APP_VERSION=${VERSION}

WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY app/package.json ./
COPY app/src ./src

USER node
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s \
  CMD wget -qO- http://127.0.0.1:8080/health || exit 1

# run node directly so it gets SIGTERM
CMD ["node", "src/server.js"]
