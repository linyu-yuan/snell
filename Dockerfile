FROM debian:stable-slim
COPY snell-server /usr/local/bin/snell-server
RUN chmod +x /usr/local/bin/snell-server
WORKDIR /etc/snell
ENTRYPOINT ["/usr/local/bin/snell-server"]
