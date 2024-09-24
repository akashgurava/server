FROM --platform=linux/arm64 postgres:latest

RUN apt-get update && apt-get install -y \
    wget brotli\
    && rm -rf /var/lib/apt/lists/*

# Install Prometheus backup tools
RUN wget https://github.com/prometheus/prometheus/releases/download/v2.37.0/prometheus-2.37.0.linux-arm64.tar.gz \
    && tar xvfz prometheus-2.37.0.linux-arm64.tar.gz \
    && cp prometheus-2.37.0.linux-arm64/promtool /usr/local/bin/ \
    && rm -rf prometheus-2.37.0.linux-arm64*

COPY backup.sh /backup.sh
RUN chmod +x /backup.sh

CMD ["/backup.sh"]
