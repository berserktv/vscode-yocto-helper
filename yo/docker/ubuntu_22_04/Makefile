IMAGE = ubuntu_22_04
# каталог для сборки образа внутри контейнера, такой же путь надо указать в файле Dockerfile см. метку WARNING
PUB   = "/mnt/data"
# путь до корневого каталога сборки, в котором находится файл setup-environment (если не задан, то ../docker)
YO_R ?= $(shell dirname $(shell pwd))

run:
	docker run --rm \
	--network=host \
	-v ${HOME}/.ssh:/home/user/.ssh:z \
	-v $(shell readlink -f ${SSH_AUTH_SOCK}):/ssh-agent -e SSH_AUTH_SOCK=/ssh-agent \
	--cap-add=cap_sys_admin --cap-add=cap_net_admin --cap-add=cap_net_raw \
	--mount type=bind,source=${YO_R},target=${PUB} -ti ${IMAGE}

run_detach:
	docker run --rm \
	--network=host \
	-v ${HOME}/.ssh:/home/user/.ssh:z \
	-v $(shell readlink -f ${SSH_AUTH_SOCK}):/ssh-agent -e SSH_AUTH_SOCK=/ssh-agent \
	--cap-add=cap_sys_admin --cap-add=cap_net_admin --cap-add=cap_net_raw \
	--mount type=bind,source=${YO_R},target=${PUB} -d -t ${IMAGE}

build:
	docker build -f Dockerfile --tag ${IMAGE} .

rebuild:
	docker build -f Dockerfile --no-cache --tag ${IMAGE} .
	
install:
	sudo apt-get update
	sudo apt-get install -y docker.io
	
# удаление всех остановленных контейнеров, 
clean-all-container:
	sudo docker rm $(docker ps -qa)
	
	
.PHONY: run build clean-all-container
