ARG BASE_IMAGE
FROM ${BASE_IMAGE}
# Exact vendor zlib fix; inherit the upstream entrypoint and user policy.
RUN apk add --no-cache --upgrade zlib=1.3.2-r1
LABEL cn.pawday.security-baseline="2026-10-13"
