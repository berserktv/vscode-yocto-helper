FROM ubuntu:22.04
# Switch Ubuntu to non-interactive mode to avoid unnecessary prompts
ENV DEBIAN_FRONTEND noninteractive

# WARNING PUB = "/mnt/data"
#
RUN mkdir -p "/mnt/data"

# Install Midnight Commander and reconfigure locales
RUN apt update && \
    apt -y install \
    mc language-pack-ru \
    && locale-gen ru_RU.UTF-8 en_US.UTF-8 \
    && dpkg-reconfigure locales

RUN echo "LANG=ru_RU.UTF-8" >> /etc/default/locale \
    && echo "LANGUAGE=ru_RU.UTF-8" >> /etc/default/locale

ENV LANG ru_RU.UTF-8
ENV LANGUAGE ru_RU.UTF-8

# Install Yocto Project dependencies
RUN	apt -y install \
    gawk wget git-core diffstat unzip texinfo gcc-multilib \
    build-essential chrpath socat libsdl1.2-dev xterm cpio lz4 zstd

### RUN echo 'root:docker' | chpasswd

# Create Docker user
RUN groupadd -f --gid 1000 user \
    && useradd --uid 1000 --gid user --shell /bin/bash --create-home user

# Note: To connect to a running container as root (check container hash with docker ps)
# docker exec -u 0 -it hash_container bash
USER user
WORKDIR /mnt/data
ENTRYPOINT ["./shell.sh"]
