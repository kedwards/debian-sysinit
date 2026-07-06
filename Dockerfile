FROM debian:trixie-slim

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install --no-install-recommends -y \
      bash \
      ca-certificates \
      cloud-image-utils \
      coreutils \
      cpio \
      curl \
      gzip \
      libnss-wrapper \
      openssh-client \
      openssl \
      python3 \
      qemu-system-x86 \
      qemu-utils \
      xorriso && \
    rm -rf /var/lib/apt/lists/*
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]

CMD ["bash"]
