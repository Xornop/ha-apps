FROM onerahmet/openai-whisper-asr-webservice:latest

RUN apt-get update && apt-get install -y jq && rm -rf /var/lib/apt/lists/*

COPY run.sh /run.sh
RUN chmod +x /run.sh

ENTRYPOINT ["/run.sh"]
