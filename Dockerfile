FROM docker.io/library/nginx:alpine
COPY nginx.conf /etc/nginx/nginx.conf

COPY site/ /usr/share/nginx/html/
RUN adduser -D -H -s /sbin/nologin web && \
    chown -R web:web /usr/share/nginx/html && \
    sed -i 's/user  nginx;/user  web;/' /etc/nginx/nginx.conf
EXPOSE 80
HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
  CMD wget -q -O - http://127.0.0.1/ > /dev/null || exit 1

