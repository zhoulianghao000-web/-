ARG BASE_IMAGE
FROM ${BASE_IMAGE}
# Exact vendor zlib fix; inherit the upstream entrypoint and user policy.
RUN apk add --no-cache --upgrade zlib=1.3.2-r1 su-exec && \
    if [ -f /usr/local/bin/gosu ]; then \
      rm /usr/local/bin/gosu && sed -i 's/exec gosu /exec su-exec /g' /usr/local/bin/docker-entrypoint.sh; \
    fi
LABEL cn.pawday.security-baseline="2026-10-13"
