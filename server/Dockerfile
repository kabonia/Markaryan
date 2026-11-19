FROM node:22-alpine
WORKDIR /app
# GigaChat uses certificates of the Russian Trusted Root CA (НУЦ Минцифры).
ADD https://gu-st.ru/content/lending/russian_trusted_root_ca_pem.crt /usr/local/share/ca-certificates/russian_trusted_root_ca.pem
ENV NODE_EXTRA_CA_CERTS=/usr/local/share/ca-certificates/russian_trusted_root_ca.pem \
    NODE_ENV=production \
    DATA_DIR=/app/data
COPY package.json ./
COPY src ./src
COPY scripts ./scripts
COPY market-prices ./market-prices
RUN mkdir -p /app/data && chown -R node:node /app
USER node
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s CMD wget -qO- http://127.0.0.1:8080/health || exit 1
CMD ["node", "src/index.js"]
