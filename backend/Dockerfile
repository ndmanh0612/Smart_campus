FROM node:24-bookworm-slim@sha256:01d566e8d94d8c619591d78652babfccd3c6992a3dffa9ed5ab39e11cf6c70e9
WORKDIR /app
COPY backend/package*.json ./backend/
RUN cd backend && npm ci --omit=dev --ignore-scripts
COPY backend/src ./backend/src
COPY backend/server.ts backend/bootstrap.ts backend/migrate.ts backend/seed.ts ./backend/
COPY database ./database
COPY flutter/app/build/web ./flutter/app/build/web
USER node
EXPOSE 8081
HEALTHCHECK --interval=10s --timeout=5s --retries=6 CMD node -e "fetch('http://127.0.0.1:8081/readyz').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
CMD ["node","backend/server.ts"]
