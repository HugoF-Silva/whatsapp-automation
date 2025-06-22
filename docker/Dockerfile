FROM node:18-alpine
WORKDIR /app
COPY infra .
RUN npm ci
EXPOSE 3000
CMD ["node", "server.js"]
