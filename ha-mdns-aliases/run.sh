#!/usr/bin/with-contenv bashio
set -e

bashio::log.info "Starting HA mDNS Aliases"
exec python3 -u /responder.py
