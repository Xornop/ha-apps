FROM ventura8/whisper-pro-asr:latest

USER root

RUN apt-get update && apt-get install -y jq curl && rm -rf /var/lib/apt/lists/*

COPY run.sh /run.sh
RUN chmod +x /run.sh

ENTRYPOINT ["/run.sh"]
