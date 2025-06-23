FROM node:18-alpine
WORKDIR /usr/src/app

# Install n8n globally
RUN npm install -g n8n

# Copy any custom init script
COPY init.js ./init.js

EXPOSE 5678
CMD ["n8n", "start", "--tunnel"]