
ARG BUILD_FROM
FROM ${BUILD_FROM}
 
RUN apk add --no-cache curl
 
# Pull the prefetcharr binary from the upstream Docker image
COPY --from=phueber/prefetcharr:latest /prefetcharr /usr/local/bin/prefetcharr
COPY --from=phueber/prefetcharr:latest /cmd.sh /cmd.sh
 
RUN chmod +x /usr/local/bin/prefetcharr
 
COPY run.sh /run.sh
RUN chmod +x /run.sh
 
CMD ["/run.sh"]
 
