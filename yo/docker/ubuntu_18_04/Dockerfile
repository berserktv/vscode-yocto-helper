FROM ubuntu:18.04
# Переключаю Ubuntu в неинтерактивный режим — чтобы избежать лишних запросов
ENV DEBIAN_FRONTEND noninteractive 

# WARNING PUB = "/mnt/docker/ubuntu_18_04"
#
RUN mkdir -p "/mnt/docker/ubuntu_18_04"

# Устанавливаю локаль и mc
RUN apt update && apt -y upgrade \
    && apt -y install \
    mc language-pack-ru \
    && locale-gen ru_RU.UTF-8 \
    && locale-gen en_US.UTF-8 \
    && dpkg-reconfigure locales

RUN echo "LANG=ru_RU.UTF-8" >> /etc/default/locale \
    && echo "LANGUAGE=ru_RU.UTF-8" >> /etc/default/locale

ENV LANG ru_RU.UTF-8
ENV LANGUAGE ru_RU.UTF-8
 
# Устанавливаю зависимости Yocto Project
RUN	apt -y install \
	gawk wget git-core diffstat unzip texinfo gcc-multilib \
    build-essential chrpath socat libsdl1.2-dev xterm

RUN	apt -y install iputils-ping

# дополнительные пакеты, исправляющие ошибки сборки для 18.04
RUN	apt -y install python-pip cpio

RUN echo 'root:docker' | chpasswd

# Создание пользователя докера
RUN groupadd --gid 1000 user \
	&& useradd --uid 1000 --gid user --shell /bin/bash --create-home user

RUN chown -R user:user /home/user

# Примечание: для подключения к работающему контейнеру под root (hash см. docker ps)
# docker exec -u 0 -it hash_container bash
USER user
ENTRYPOINT /bin/bash
