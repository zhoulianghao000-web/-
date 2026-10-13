FROM opensearchproject/opensearch:3.9.0@sha256:adfa61f85025d06b4aeb562e7e74fde7e31c437039c93c3862c17e9acebd6c7c
USER root
# Frozen Amazon Linux security repository snapshot; keep OpenSearch 3.9 data/index format.
RUN dnf --releasever=2023.12.20261012 upgrade -y && dnf clean all
USER 1000
LABEL cn.pawday.security-baseline="2026-10-13"
