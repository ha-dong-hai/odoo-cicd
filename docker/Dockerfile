# Custom Odoo image: official odoo:19.0 base + our addons + extra pip deps.
# This mirrors what Odoo.sh's own container does (Ubuntu base, Odoo source,
# your repo's code, requirements.txt installed automatically) - see
# docker/odoo.conf.template and docker-entrypoint.sh for the rest.
FROM odoo:19.0

USER root

# gettext-base provides envsubst, used by docker-entrypoint.sh to render
# odoo.conf.template with this container's environment variables.
RUN apt-get update \
    && apt-get install -y --no-install-recommends gettext-base \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt /tmp/requirements.txt
RUN if [ -s /tmp/requirements.txt ]; then \
      pip3 install --break-system-packages --no-cache-dir -r /tmp/requirements.txt; \
    fi \
    && rm -f /tmp/requirements.txt

COPY addons/ /mnt/extra-addons/
COPY docker/odoo.conf.template /etc/odoo/odoo.conf.template
COPY docker/docker-entrypoint.sh /docker-entrypoint.sh

RUN chown -R odoo:odoo /mnt/extra-addons \
    && chmod +x /docker-entrypoint.sh

USER odoo
ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["odoo"]
