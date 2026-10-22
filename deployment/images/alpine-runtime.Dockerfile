ARG BASE_IMAGE
FROM ${BASE_IMAGE}
# Keep all musl subpackages on the same vendor security fix for each pinned branch.
RUN case "$(cat /etc/alpine-release)" in \
      3.22.*) musl_version=1.2.5-r13 ;; \
      3.23.*) musl_version=1.2.5-r24 ;; \
      3.24.*) musl_version=1.2.6-r3 ;; \
      *) echo "Unsupported Alpine security branch" >&2; exit 1 ;; \
    esac && \
    apk add --no-cache --upgrade zlib=1.3.2-r1 su-exec "musl=$musl_version" && \
    if apk info --installed musl-utils >/dev/null 2>&1; then \
      apk add --no-cache --upgrade "musl-utils=$musl_version"; \
    fi && \
    if [ -f /usr/local/bin/gosu ]; then \
      rm /usr/local/bin/gosu && sed -i 's/exec gosu /exec su-exec /g' /usr/local/bin/docker-entrypoint.sh; \
    fi
LABEL cn.pawday.security-baseline="2026-10-13" \
      cn.pawday.security-patch="2026-10-22-CVE-2026-107891"
