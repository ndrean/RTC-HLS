FROM ghcr.io/livebook-dev/livebook:latest


RUN apt update && apt upgrade -y && \
    apt install pkg-config libssl-dev libsrtp2-dev -y && \
    apt purge -y && apt clean -y && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /data
ENV LIVEBOOK_HOME=/data
ENV HOME=/home/livebook
ENV LIVEBOOK_IP="::"


#RUN mkdir $HOME && chmod 777 $HOME
#RUN chmod -R go= /app
#RUN chmod -R go=u $HOME
HEALTHCHECK CMD wget --no-verbose --tries=1 --spider http://localhost:${LIVEBOOK_PORT-8080}/public/health || exit 1

CMD ["/app/bin/server"]
