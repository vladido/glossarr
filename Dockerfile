FROM node:alpine
ARG VCS_REF=unknown
LABEL org.opencontainers.image.revision="$VCS_REF"

RUN apk add --no-cache openssl

WORKDIR /app

COPY package.json .
COPY proxy.js .

EXPOSE 3000 3443
# GLOSSARR_PORT overrides 3443 (e.g. set to 443 for direct Docker network use)

CMD ["node", "proxy.js"]
