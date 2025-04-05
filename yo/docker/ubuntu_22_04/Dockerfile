FROM ubuntu:22.04
# Переключаю Ubuntu в неинтерактивный режим — чтобы избежать лишних запросов
ENV DEBIAN_FRONTEND noninteractive 

# WARNING PUB = "/mnt/data"
#
RUN mkdir -p "/mnt/data"

# Устанавливаю локаль и mc
RUN apt update && \
    apt -y install \
    mc language-pack-ru \
    && locale-gen ru_RU.UTF-8 en_US.UTF-8 \
    && dpkg-reconfigure locales

RUN echo "LANG=ru_RU.UTF-8" >> /etc/default/locale \
    && echo "LANGUAGE=ru_RU.UTF-8" >> /etc/default/locale

ENV LANG ru_RU.UTF-8
ENV LANGUAGE ru_RU.UTF-8
 
# Устанавливаю зависимости Yocto Project
RUN	apt -y install \
    gawk wget git-core diffstat unzip texinfo gcc-multilib \
    build-essential chrpath socat libsdl1.2-dev xterm cpio lz4 zstd

RUN echo 'root:docker' | chpasswd

# Создание пользователя докера
RUN groupadd -f --gid 1000 user \
	&& useradd --uid 1000 --gid user --shell /bin/bash --create-home user

# Примечание: для подключения к работающему контейнеру под root (hash см. docker ps)
# docker exec -u 0 -it hash_container bash
USER user
WORKDIR /mnt/data
ENTRYPOINT ["./shell.sh"]
