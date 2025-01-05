IMAGE=ubuntu_18_04_for_rpi
# каталог для сборки образа внутри контейнера, такой же путь надо указать в файле Dockerfile см. метку WARNING
PUB   = "/mnt/docker/ubuntu_18_04"
SRC   = $(shell dirname $(shell pwd))
# путь до корневого каталога сборки, в котором находится файл setup-environment
ROOTD = "../../../../../../"

run:
	sudo docker run --rm \
	--network=host \
	-v ${HOME}/.ssh:/home/user/.ssh:z \
	-v $(shell readlink -f ${SSH_AUTH_SOCK}):/ssh-agent -e SSH_AUTH_SOCK=/ssh-agent \
	--cap-add=cap_sys_admin --cap-add=cap_net_admin --cap-add=cap_net_raw \
	--mount type=bind,source=${SRC}/${ROOTD},target=${PUB} -ti ${IMAGE}

run_detach:
	sudo docker run --rm \
	--network=host \
	-v ${HOME}/.ssh:/home/user/.ssh:z \
	-v $(shell readlink -f ${SSH_AUTH_SOCK}):/ssh-agent -e SSH_AUTH_SOCK=/ssh-agent \
	--cap-add=cap_sys_admin --cap-add=cap_net_admin --cap-add=cap_net_raw \
	--mount type=bind,source=${SRC}/${ROOTD},target=${PUB} -d -t ${IMAGE}

build:
	sudo docker build -f Dockerfile --tag ${IMAGE} ..

rebuild:
	sudo docker build -f Dockerfile --no-cache --tag ${IMAGE} ..
	
install:
	sudo apt-get update
	sudo apt-get install -y docker.io
	
# удаление всех остановленных контейнеров, 
clean-all-container:
	sudo docker rm $(docker ps -qa)
	
	
.PHONY: run build clean-all-container
