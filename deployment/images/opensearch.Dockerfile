FROM opensearchproject/opensearch:3.9.0@sha256:adfa61f85025d06b4aeb562e7e74fde7e31c437039c93c3862c17e9acebd6c7c
USER root
# Frozen Amazon Linux security repository snapshot; keep OpenSearch 3.9 data/index format.
RUN dnf --releasever=2023.12.20261012 upgrade -y && dnf clean all
COPY deployment/images/patch-opensearch-libraries.py deployment/images/opensearch-library-patches.json /tmp/pawday-os-patches/
RUN python3 /tmp/pawday-os-patches/patch-opensearch-libraries.py
# The local/CI profiles disable the Security plugin and do not use SAML.
# Its shaded SAML bundle embeds vulnerable Jackson copies; remove that unused surface.
RUN rm /usr/share/opensearch/plugins/opensearch-security/opensaml-3.9.0.0-all.jar
USER 1000
LABEL cn.pawday.security-baseline="2026-10-13"
