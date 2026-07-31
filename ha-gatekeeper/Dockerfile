ARG BUILD_FROM
FROM $BUILD_FROM

# Python deps
COPY app/requirements.txt /app/requirements.txt
RUN pip3 install --no-cache-dir -r /app/requirements.txt

# App code
COPY app/ /app/

# s6-overlay service
COPY rootfs/ /
RUN chmod a+x /etc/services.d/ha-gatekeeper/run /etc/services.d/ha-gatekeeper/finish

WORKDIR /app
