# Worker (bot Discord + tâches planifiées) : bundle autonome, sans node_modules.
#   docker build -f apps/worker/Dockerfile -t victorious-worker .
FROM node:22-alpine AS deps
RUN corepack enable
WORKDIR /app
COPY pnpm-lock.yaml pnpm-workspace.yaml package.json ./
COPY apps/web/package.json apps/web/
COPY apps/worker/package.json apps/worker/
COPY packages/core/package.json packages/core/
COPY packages/db/package.json packages/db/
RUN pnpm install --frozen-lockfile

FROM deps AS build
COPY . .
RUN pnpm --filter @vk/worker build

FROM node:22-alpine AS run
WORKDIR /app
ENV NODE_ENV=production MIGRATIONS_DIR=/app/drizzle
RUN addgroup -S app && adduser -S app -G app && echo '{"type":"module"}' > package.json
COPY --from=build --chown=app:app /app/apps/worker/dist ./dist
COPY --from=build --chown=app:app /app/packages/db/drizzle ./drizzle
USER app
# Applique les migrations au démarrage (verrou Postgres), puis lance bot + tâches.
CMD ["node", "--enable-source-maps", "dist/index.js"]
