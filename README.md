# Причесываем VSCode до неприличной Yocto IDE или история одной кнопки

![](https://habrastorage.org/webt/0m/6i/xw/0m6ixw8xy0_7wdkr1xw1smlfui0.png)

Идея написания этой статьи вдруг возникла у меня в начале 2025 года, когда я проснулся 2 января с тяжелой головой и вдруг понял что нужно сделать что то хорошее, что то хорошее для вас, как говорит моя дочь Маргарита «для тех кто в Интернете». Как минимум мне нужен компьютерный класс на Raspberry Pi4, ну или хотя бы ферма docker(ов).

Я обожаю Visual Studio Code, но мне всегда не хватает времени чтобы более детально разобраться в его огромной функциональности, в различных конфигурациях, тасках и launch(ах) описанных в формате json и я решил это обойти. По сути мне всегда не доставало нескольких пунктов меню, которые выполняют очень специфические функции, нужные мне в процессе сборки дистрибутива в системе Yocto Project для формирования встраиваемых (Embedded) прошивок.

Началось все с того, что нужное мне меню должно быть всегда под рукой, а лучшего места чем панель Status Bar в VSCode даже не придумать, ближе некуда и я начал искать какой нибудь плагин предоставляющий эту возможность. Статья из серии DockerFace.

Краткое содержание статьи:
- Выбор и настройка плагина для VSCode
- Запись Yocto образа на SD карту памяти
- Сборка Yocto образа в Docker(е)
- Прием Барона Мюнхгаузена для документирования bash
- Запуск Yocto образа RPi под виртуальной машиной Qemu
- Развертывание DemoMinimal образа из Yocto коробки
- Выписываем Buster Slim(а) для крутой разборке в Докере
- Настройка DHCP, TFTP и NFS сервера
- Загрузка core-image-minimal (wic) образа на rpi4 по сети
- Сетевая загрузка Raspbian для платы Raspberry Pi4
- Побочный эффект сборки, загрузка ISO дистрибутива Ubuntu по сети
- Автоматический анализ Yocto логов с помощью Deepseek
- самая красивая кнопка для друзей Элвиса
- встраиваем кнопки в VSCode паровозиком

## Выбор плагина для VSCode

Плагин называется "VsCode Action Buttons" (seunlanlege.action-buttons), он делает именно то что мне и было нужно, позволяет прикрутить любой bash код по нажатию кнопки.

Первым делом необходимо установить как сам VSCode (если он у вас еще не установлен), так и сам плагин:

```bash
sudo apt install -y snap
sudo snap install --classic code
code --install-extension seunlanlege.action-buttons
```

Настройки плагина добавляются в `.vscode/settings.json` и вызов shell скрипта, выглядит так:

```json
...
"actionButtons": {
    "reloadButton": null,
    "loadNpmCommands": false,
    "commands": [
        {
            "name": "Button-1",
            "singleInstance": true,
            "color": "#007fff",
            "command": ".vscode/script1.sh",
        },
        {
            "name": "Button-N",
            "singleInstance": true,
            "color": "#ff007f",
            "command": ".vscode/scriptN.sh",
        }
    ]
}
```

Примечание: в моем случае это bash код, но запускаемый код может быть и на любом другом языке, можно и просто исполняемый бинарный файл запустить, кому как нравиться.


## Запись Yocto образа на карту памяти

Первым делом в Yocto мне нужно было записать результат сборки на карту памяти microSDHC подключенную с помощью картридера. Эта SD карта в дальнейшем вставляется в одноплатный компьютер, например Raspberry Pi 4, и плата с нее загружается.

Вся необходимая мне функциональность находится в одном общем файле `.vscode/yo/func.sh`
и запускать функции я буду оттуда.

Итак вначале мне нужно найти список возможных файлов образов, для записи на карту SD, название целевой платформы YO_M берется из основного конфигурационного файла "build/conf/local.conf", расширение файла для записи командой dd содержится в переменной `YO_EXT`.

```bash
YO_EXT=".wic .rootfs.wic .rootfs.wic.bz2 .rpi-sdimg .wic.bz2"

find_name_image() {
  IFS=$' '
  YO_IMAGE_NAME=""
  if [ -z "$YO_M" ]; then echo "MACHINE variable not found"; return -1; fi

  for ext in ${YO_EXT}; do
      local find_str=$(ls -1 ${YO_DIR_IMAGE}/${YO_M} | grep "${YO_M}${ext}$")
      if [ -z "$find_str" ]; then
          echo "NAME IMAGE ${YO_M}${ext} is not found => ${YO_DIR_IMAGE}/${YO_M}"
      else
          YO_IMAGE_NAME="$YO_IMAGE_NAME $find_str"
          echo "find: YO_IMAGE_NAME=$YO_IMAGE_NAME"
      fi
  done

  [[ -z "${YO_IMAGE_NAME}" ]] && return 1
  YO_IMAGE_NAME=$(echo "$YO_IMAGE_NAME" | tr '\n' ' ')
  return 0
}
```

Результат работы функции `find_name_image` будет содержаться в строковой переменной `YO_IMAGE_NAME`, названия найденных образов разделены пробелами.

Далее мне необходимо найти SD карту подключенную через usb или картридер, формируется очень удобный табличный формат вывода, который позволяет убедиться что выбрано именно то устройство, которое нужно, так как после записи командой dd все текущие данные удаляются и тут главное не ошибиться.

```bash
find_sd_card() {
  IFS=$'\n'
  LI_DISK=""
  echo "Disk devices in the system:"
  echo "┌────┬──────┬──────┬──────────────────────────────┐"
  echo "Name | Type | Size | Model                        |"
  echo "├────┴──────┴──────┴──────────────────────────────┘"
  lsblk -o NAME,TYPE,SIZE,MODEL | grep -E 'disk|mmcblk|sd.*'
  echo "└─────────────────────────────────────────────────┘"
  local bn;
  local list=$(ls -l /dev/disk/by-id/usb* 2>/dev/null)
  if [ $? -eq 0 ]; then
      for i in $list; do
          bn=$(basename $i)
          if ! echo "$bn" | grep -q "[0-9]"; then LI_DISK+="$bn "; fi
      done
  fi

  list=$(ls -l /dev/disk/by-id/mmc* 2>/dev/null)
  if [ $? -eq 0 ]; then
      for i in $list; do
          bn=$(basename $i)
          if ! echo "$bn" | grep -q "p[0-9]"; then LI_DISK+="$bn "; fi
      done
  fi
  if [ -n "$LI_DISK" ]; then echo "LIST SD card => $LI_DISK"; return 0;
  else echo "SD card not found => exiting ..."; return 1; fi
}
```

Все найденные возможные носители содержаться в переменной `LI_DISK` и в функции `select_dd_info` предлагается список пунктов от 1 до N, возможная комбинация варианта команды dd для образа и диска.

Для записи нужно выбрать то что вы хотите записать, ввести номер и нажать ввод, запись осуществляется с помощью команды sudo, так что у вас есть еще одна возможность убедиться в правильности выбора устройства.

Если файл образа содержится в архиве bz2, то перед записью образ будет распакован.

```bash
select_dd_info() {
  local j=1
  IFS=$' '
  for i in $LI_DISK; do
      for image in $YO_IMAGE_NAME; do
          if echo "$image" | grep -q "\.wic\.bz2"; then
              echo "$j) bzip2 -dc $image | sudo dd of=/dev/$i bs=1M"
          else
              echo "$j) dd if=$image of=/dev/$i bs=1M"
          fi
          j=$((j+1))
      done
  done

  echo -n "=> Select the option. WARNING: the data on the disk will be DELETED:"
  read SEL

  j=1
  for i in $LI_DISK; do
      for image in $YO_IMAGE_NAME; do
          if [ $SEL == "$j" ]; then
              mount | grep "^/dev/$i" | awk '{print $1}' | xargs -r sudo umount
              if echo "$image" | grep -q "\.wic\.bz2"; then
                  echo "bzip2 -dc $image | sudo dd of=/dev/$i bs=1M"
                  bzip2 -dc $image | sudo dd of=/dev/$i bs=1M; sync
              else
                  echo "sudo dd if=$image of=/dev/$i bs=1M"
                  sudo dd if=$image of=/dev/$i bs=1M; sync
              fi
          fi
          j=$((j+1))
      done
  done
}
```

Если на выбранном диске уже есть подмонтированные разделы, то перед записью они должны быть размонтированы. Для записи дистрибутива на карту памяти используется функция `sdcard_deploy`:

```bash
sdcard_deploy() {
  if find_sd_card && find_name_image; then
      cd "${YO_DIR_IMAGE}/${YO_M}"
      select_dd_info
  fi
}
```

Функциональность из скрипта .vscode/yo/func.sh лучше разделять, так как функций можно наколотить множество и со временем, они перемешиваются:

то работающие, то устаревшие, то еще какие нибудь и то что проверено можно выносить в отдельный скрипт, покажу на примере `.vscode/yo/sdcard_deploy.sh`:

```bash
#!/bin/bash
this_f=$(readlink -f "$0")
this_d=$(dirname "$this_f")
source $this_d/func.sh
sdcard_deploy
```

Особенно это хорошо подходит для разделения функциональности, один работающий скрипт, который выполняет по возможности одну и только одну функцию верхнего уровня.

Команды readlink и dirname используются для формирования абсолютных путей до запускаемого файла и каталога, а то с путями всегда возникает путаница, а так путь абсолютный и проблем меньше.

Итак нажал кнопку в строке состояния VSCode, выбрал образ и диск для записи, и дистрибутив записался `.vscode/settings.json`:

```json
{
    "name": "SDcardDeploy",
    "singleInstance": true,
    "color": "#007fff",
    "command": "cd .vscode/yo; ./sdcard_deploy.sh",
}
```

Для плагина "seunlanlege.action-buttons" текущим является каталог, в котором находиться конфигурация .vscode, поэтому перед вызовом функции записи меняю текущий каталог, это скорее соглашение вызова, чтобы команды для кнопок добавлять похожим образом, для переменной "YO_R"
у меня есть дополнительная проверка, которая срабатывает если изначальный относительный путь для этой переменной указан неправильно:

```bash
# корневой каталог yocto, где будет располагаться каталог build, относительно текущего каталога
YO_R="../.."
find_setup_env() {
    if [ -f "${YO_R}/setup-environment" ]; then return 0; fi
    local tmp_path=".."
    for i in {1..7}; do
        if [ -f "${tmp_path}/setup-environment" ]; then
            export YO_R=$(realpath "${tmp_path}")
            return 0;
        fi
        tmp_path="${tmp_path}/.."
    done
    echo "error: 'setup-environment' not found in parent directories, env: 'YO_R' wrong path ..."; return 1
}
find_setup_env
```


Этот код находиться в самом начале скрипта `func.sh`, здесь корневой каталог определяется по наличию файла `setup-environment`, который отвечает за формирование первоначальной структуры дерева каталогов сборки, такого как:

```dart
 корневой каталог Yocto
    ├── build
    ├── downloads
    ├── setup-environment
    ├── shell.sh
    └── sources
```


## Сборка Yocto образа в Docker

Следующая функция для VSCode, которая мне нужна, это функция позволяющая собирать дистрибутив Yocto разными тулчейнами. Для старых Yocto веток, на новых хост системах, например в Ubuntu 24.04 все ну постоянно отваливается, то gcc не той версии, то линковщик, а то и вообще cmake ну совсем старый нужен.

Как то всегда возникает полная несовместимость инструментов сборки и того, что я хочу собрать, сейчас без Docker(а) в старые сборки лучше и не соваться, прямо беда, беда. 

Да и в новые тоже, рекомендую сборку осуществлять всегда только в докере.

Конфигурацию докера(ов) располагается в каталоге `.vscode/yo/docker`, например => `ubuntu_22_04`

```dart
    yo
    ├── build_image.sh
    ├── docker
    │   └── ubuntu_22_04
    │       ├── Dockerfile
    │       └── Makefile
    ├── func.sh
    └── sdcard_deploy.sh
```

Содержание Dockerfile следующее:

```dart
FROM ubuntu:22.04
# Переключаю Ubuntu в неинтерактивный режим — чтобы избежать лишних запросов
ENV DEBIAN_FRONTEND noninteractive

# WARNING PUB = "/mnt/data"
#
RUN mkdir -p "/mnt/data"

# Устанавливаю mc и перенастраиваю locales
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
```

Контейнер запускается под пользователем user, но в случае каких либо непредвиденных проблем, добавляется пароль "docker" для пользователя root и вы можете подключиться работающему к контейнеру под root(ом), и например установить какой нибудь пакет, с использованием команды apt.

После устранения проблемы зависимостей, можно название этих недостающих пакетов добавить в Dockerfile напрямую, а как отладили образ для контейнера, строку можно закомментировать.

Для работы с докером служит Makefile:

```dart
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
```


Здесь докер запускается следующим образом:

```cmake
docker run --rm \
  --network=host \
  -v ${HOME}/.ssh:/home/user/.ssh:z \
  -v $(shell readlink -f ${SSH_AUTH_SOCK}):/ssh-agent \
  -e SSH_AUTH_SOCK=/ssh-agent \
  --cap-add=cap_sys_admin \
  --cap-add=cap_net_admin \
  --cap-add=cap_net_raw \
  --mount type=bind,source=${YO_R},target=${PUB} \
  -d -t ${IMAGE}
```

где

* rm — автоматическое удаление контейнера после завершения его работы;
* network=host — c этим параметром устраняется сетевая изолированность;
  между контейнером и хостом Docker и напрямую используются сетевые ресурсы хоста, это небезопасно для хоста,
  и может применяться только в том случае, если вы знаете, что данный контейнер предназначен для внутренней закрытой извне сети;
* v (или --volume) используется docker(ом) для создания пространства хранения внутри контейнера,
  которое отделено от остальной части файловой системы контейнера, том не увеличивает размер контейнера,
  в данном случае пробрасывается сокет c ssh-agent(ом) запущенном на хосте для работы ssh авторизации внутри контейнера;
* cap-add=cap_net_admin привилегия, которая позволяет монтировать и размонтировать файловые системы;
* cap-add=cap_sys_admin предоставляет контейнеру набор системных привилегий, но не делает его полностью привилегированным;
* cap-add=cap_net_raw привилегия дающая право на создание RAW и PACKET сокетов в контейнере,
  в частности эта привилегия необходима для получения и отправки ICMP пакетов в контейнере;
* mount опция монтирования, которая пробрасывает корневой yocto каталог, в котором также располагается каталог build,
  он содержит все артефакты сборки, таким образом весь результат работы контейнера сохраняется в хост системе,
  этим я обеспечиваю то, что можно беспрепятственно останавливать и удалять контейнер, а в новом запуске
  можно продолжить работу на тех же артефактах. После первого запуска переменных среды yocto (setup-environment),
  сборочный путь жестко прописывается в конфигурационных скриптах и при изменении точки монтирования PUB
  /mnt/data на другую сборка внутри контейнера не будет работать,
  при проверке путей сборки в bitbake вы получите сообщение об ошибке (но это особенность системы сборки yocto);
* d запуск контейнера в фоне;
* t обеспечение контейнеру запуск псевдотерминала tty, контейнер не завершит свою работу, пока сеанс терминала не закончиться.

Переменная `IMAGE` указывает основное имя с которым контейнер будет запущен.

Так же если вы хотите запустить докер не в фоне, а на переднем плане, нужно убрать опцию "-d" и добавить опцию "-i", чтобы контейнер запускался в интерактивном режиме, когда можно напрямую вводить команды в работающей оболочке контейнера, в Makefile я разделяю эти режимы:

- make run - интерактивный режим с инициализацией yocto (выполнение setup-environment);
- make run_detatch - фоновый запуск контейнера, для того, чтобы подключиться к уже запущенному контейнеру,
  для выполнения одной команды bitbake,
  при каждом запуске создается shell сеанс с инициализацией setup-environment
  и последующим выполнением в нем пользовательской команды.


Далее для работы с этим Makefile(лом) мне нужно в `.vscode/yo/func.sh` добавить функцию поиска идентификатора запущенного Docker контейнера:


```bash
CONTAINER_ID=""
CONTAINER_NAME=""
DOCKER_DIR=""
find_docker_id() {
    local id=$(docker ps | grep -m1 $CONTAINER_NAME | cut -d" " -f1)
    if [ -z "$id" ]; then CONTAINER_ID=""; return 1;
    else CONTAINER_ID=$id; return 0; fi
}
```

результат поиска сохраняется в переменой `CONTAINER_ID`
и используется в функции запуска команд внутри контейнера start_cmd_docker():

```bash
start_cmd_docker() {
  if [ -z "$1" ]; then
      echo "error: start_cmd_docker(), arg1 command name empty ..."
      return 1;
  fi

  local cmd_args=$1
  check_build_dir_exist
  [[ $? -eq 2 ]] && return 2

  cd "${DOCKER_DIR}" && make build
  if ! find_docker_id; then
      make run_detach
      if ! find_docker_id; then
          echo "failed to start container => make run_detach ..."
          cd "${CURDIR}"
          return 3;
      fi
  fi

  echo "docker exec -it ${CONTAINER_ID} bash -c \"$cmd_args\""
  docker exec -it ${CONTAINER_ID} bash -c "$cmd_args"
  cd "${CURDIR}"
}
```

где первым аргументом можно передать команду или список команд, которые разделяются символом ";"
Здесь главное, чтобы переменная `DOCKER_DIR` содержала правильный путь до каталога с Makefile для Docker(a).

Функция `start_cmd_docker` вначале ищет hash идентификатор контейнера по имени, которое можно посмотреть в Makefile, см. IMAGE=ubuntu_22_04, и если контейнер не запущен, то он запускается в фоновом режиме (make run_detach) и далее через команду docker exec идет подключение и запуск нового bash процесса, в котором и происходит выполнение переданных первым аргументом команд см. `$cmd_args`

Есть еще дополнительная проверка, на наличие каталога сборки build, и если его нет, то команды в контейнере запущены не будут.

Работа с этой функцией описана в shell скрипте `.vscode/yo/build_image.sh`

```bash
  #!/bin/bash
  this_f=$(readlink -f "$0")
  this_d=$(dirname "$this_f")
  source $this_d/func.sh

  cmd_runs="$1"
  DOCKER_DIR="docker/ubuntu_22_04"
  CONTAINER_NAME="ubuntu_22_04"
  cmd_init="cd /mnt/data; MACHINE=$YO_M source ./setup-environment build"
  start_cmd_docker "${cmd_init}; ${cmd_runs}"
```


Процесс запуска разделяется на две части:
статическую: cmd_init и динамическую cmd_run, со списком команд, которые вы хотите запустить внутри Yocto среды, например:

- bitbake имя_образа_для_сборки;
- bibbake имя_отдельного_рецепта_для_сборки;
- и т.д.

cmd_init осуществляет  запуск Yocto среды сборки под указанную целевую платформу, скрипту setup-environment
передается название платформы (берется из build/conf/local.conf).

Запуск скрипта build_image.sh, по нажатию кнопки в status bar прописывается в `.vscode/settings.json` так:

```json
...
"actionButtons": {
  "reloadButton": null,
  "loadNpmCommands": false,
  "commands": [
    {
      "name": "Build",
      "singleInstance": true,
      "color": "#007fff",
      "command": "cd .vscode/yo; source func.sh; DOCKER_DIR='docker/ubuntu_22_04' start_session_docker",
    },
    {
      "name": "BuildImage",
      "singleInstance": true,
      "color": "#007fff",
      "command": "cd .vscode/yo; ./build_image.sh 'bitbake core-image-minimal'",
    }
  ]
}
```

также по нажатию кнопки Build можно запустить интерактивный сеанс работы с bitbake, за это отвечает функция `start_session_docker`, описанная в .vscode/yo/func.sh:

```bash
  start_session_docker() {
      cd "${DOCKER_DIR}"
      make build && make run
      cd "${CURDIR}"
  }
```

Здесь сам запуск shell процесса описан в последней строке:
Dockerfile: ENTRYPOINT ["./shell.sh"]

В этом случае остается запущенным терминал в VSCode, к которому вы всегда сможете обращаться для работы с вашей Yocto сборкой.


## Запуск Yocto сборки для Raspberry Pi под виртуальной машиной Qemu

Следующей функцией которую я захотел добавить для VSCode является функция запуска и отладки Yocto дистрибутива без наличия платы Raspberry Pi, иногда когда платы нет под рукой не получается посмотреть вновь собранный Yocto образ, пример покажу для платы Raspberry Pi 3, так можно запустить только 64 битный образ.


```bash
start_qemu_rpi3_64() {
  local curdir=$(pwd)
  local kernel="Image"
  local dtb="${IMAGE_DTB}"
  local image="${IMAGE_NAME}"

  cd "${YO_R}/${YO_M}"
  [[ -f "${kernel}" || -f "${dtb}" || -f "${image}" ]] && return 1

  size_mb=$(( ($(stat -c %s "$image") + 1048575) / 1048576 ))
  thresholds=(64 128 256 512)

  for threshold in "${thresholds[@]}"; do
      if [ "$size_mb" -lt "$threshold" ]; then
          qemu-img resize "${image}" "${threshold}M"
      fi
  done

  qemu-system-aarch64 \
      -m 1G \
      -M raspi3b \
      -dtb ${dtb} \
      -kernel ${kernel} \
      -serial mon:stdio \
      -drive file=${image},format=raw,if=sd,readonly=off \
      -append "console=ttyAMA0,115200 root=/dev/mmcblk0p2 rw earlycon=pl011,0x3f201000" \
      -nographic
  cd ${CURDIR}
}
```

где:

`qemu-system-aarch64` - запуск Qemu для 64 битных сборок, если вдруг вы захотите запустить дистрибутив собранный под 32 битную разрядность, то вас может ждать пустой терминал, совсем пустой, ядро даже не пикнет, и в этом случае сильно помогает опция:

`-d in_asm -D QEMU_log.txt` для записи всех ассемблерных инструкций в отдельный файл, это медленно, но если вы перепутали процессорные инструкции, то вы должны об этом узнать.

Параметры:

* `m 1G` - количество оперативной памяти;
* `M raspi3b` - тип запускаемой машины Raspberry Pi 3;
* `dtb bcm2837-rpi-3-b.dtb` - указание правильного дерева устройств для нашей платы, без него
  ядро не сможет запуститься и инициализировать устройства RPI3, DTB (Device Tree Blob) описывает все компоненты платы:
  CPU, периферия, адреса памяти и прерывания для устройств;
* `kernel Image` - название файла с ядром, которое запускается;
* `serial mon:stdio` в qemu позволяет вам перенаправить выходные данные последовательного порта
  на стандартный ввод-вывод (stdout) вашей терминальной сессии, таким образом всё, что отправляется
  на последовательный порт виртуальной машины, будет выводиться в терминал, из которого вы запустили Qemu,
  и вы сможете вводить данные в виртуальную машину через тот же терминал;
* drive file=${image},format=raw,if=sd,readonly=off - подключает виртуальный диск как SD карту
  в raw (сыром) формате, при этом в самом файле содержится таблица разделов и два логических диска
  (см. `fdisk -l $image`), на втором диске находится
  корневая файловая система rootfs, диск будет доступен для записи;
* append "console=ttyAMA0,115200 root=/dev/mmcblk0p2 rw earlycon=pl011,0x3f201000"
  здесь настраивается системная консоль:
  - `console=ttyAMA0,115200` это основной канал связи между ядром Linux и пользователем;
  - `root=/dev/mmcblk0p2 rw` подключает второй логический раздел блочного устройства
    как корневую файловую систему в режиме чтение/запись;
  - `earlycon=<драйвер>,<опции>,<адрес>` выводить сообщения на этапе загрузки
    до инициализации основных драйверов, формат ввода:
    - `pl011` — это тип UART-контроллера, используемого в Raspberry Pi;
    - `адрес 0x3f201000` указывает на регистры этого контроллера в памяти,
      хочу отметить, что этот адрес специфичен для реального железа Raspberry Pi,
      в плате Raspberry Pi ttyAMA0 всегда связан с контроллером UART pl011;
* `nographic` - отключение графического вывода, при этом виртуальная машина будет работать в текстовом режиме,
  без использования стандартного графического интерфейса Qemu,
  все выводимые сообщения (включая вывод из гостевой ОС)
  отображаются в терминале, из которого была запущена виртуальная машина,
  это позволяет вести мониторинг работы системы и взаимодействовать
  с ней только через текстовые команды.


Для Qemu raspi3b используется DTB, более совместимый с эмуляцией: dtb="bcm2837-rpi-3-b.dtb".

Еще можно использовать дополнительные опции для отладки:
"-d guest_errors,unimp,cpu_reset -D QEMU.log":

Опции включают разные категории отладочной информации, информация сохраняется в отдельном файле:

* `guest_errors`: фиксирует ошибки, возникающие у гостевой операционной системы;
* `unimp`: записывает попытки использования недоступных инструкций
  или функциональности в эмулируемом устройстве;
* `cpu_reset`: фиксирует информацию, связанную с сбросом процессора.


На реальной плате Raspberry Pi 3 управляющим является GPU, он там вообще главный, а CPU полностью находится в этой зависимости. Проприетарный загрузчик bootcode.bin обычно находится на первом загрузочном разделе SD карты, и первым делом он грузит прошивку для GPU => start.elf и fixup.dat (или в зависимости от версии платы start4.elf), и передает ей управление, прошивка для GPU разбирает файл конфигурации [config.txt](https://www.raspberrypi.com/documentation/computers/config_txt.html)

формируя загрузочные параметры ядра и передает управление CPU для запуска ядра.

Представленная выше команда "qemu-system-aarch64 ..." работает немного иначе:

Во первых мы с вами убираем GPU из этой цепочки, мы его игнорируем, осуществляя прямую загрузку ядра через параметр -kernel, так быстрее и меньше ошибок, у нас конечно есть все загрузочные файлы на первом загрузочном разделе SD карты:

см `-drive file=${image}` (в системе это /dev/mmcblk0p1), но именно проверять сам механизм вторичных и третичных загрузчиков как то не хочется. 

Да и не понятно, на каком уровне работает эмуляция GPU в QEmu для `-M raspi3b`, здесь главное передать ядру актуальный dtb="bcm2837-rpi-3-b.dtb", без него то же ничего работать не будет.

Ядро запускается, инициализирует оборудование, подключает корневую файловую систему, ОС переходит на нужный уровень исполнения, запускает виртуальные терминалы `tty` через getty процессы, которые создают сессии для ввода/вывода пользователя и если мы правильно ассоциировали `getty` c нашим эмулируемым контроллером `UART pl011 => /dev/ttyAMA0` то мы увидим пользовательское приглашение login: и далее можно вводить пароль и работать.

Здесь есть еще один нюанс:

Если ничего не менять в образе, то `getty` не будет ассоциировать с `/dev/ttyAMA0` и для того, чтобы это произошло нужно еще дополнительно собрать образ с использованием:

```dart
  # это с учетом того, что система запускается через SysVinit,
  # под Systemd это не проверялось (там по другому)
  SERIAL_CONSOLES = "115200;ttyAMA0"
  SERIAL_CONSOLES_CHECK = "ttyAMA0:ttyS0"

  # эти параметры повлияют на изменения
  # системного файла /etc/inittab в образе
  # и ассоциируют getty с последовательным портом

  # Параметры добавляются в
  # конфигурационный файл слоя в `local.conf`
```

Вообщем то, получается как то совсем не удобно, специально пересобирать тот же core-image-minimal для запуска под виртуальную машину Qemu, но можно `/etc/inittab` менять на лету в `core-image-minimal.wic`, вначале смонтировать его c помощью `mount_raw_image` (см. ниже), скорректировать, сохранить изменения и вызвать `umount_raw_image` (будет время я это проверю).


## Использование приема Барона Мюнхгаузена для документирования bash

Здесь я хотел бы привести следующий пример, простого само документирования bash кода:

```bash
#!/bin/bash

help() {
    local script_path=$(realpath "${BASH_SOURCE[0]}")
    grep -A 1 "^# " "${script_path}" | sed 's/--//g'
}

# Пример bash функции 1 (входит в описание интерфейсов)
example_bash_function1() {
    echo "example_bash_function1"
}

# Пример bash функции 2 (входит в описание интерфейсов)
example_bash_function2() {
    echo "example_bash_function2"
}

#Пример bash функции 3, которая исключается из описания интерфейсов
example_bash_function3() {
    echo "example_bash_function3"
}

help
```

Это удобно тем, что если работать со скриптом через:
`source name_script.sh`
то можно сразу увидеть названия всех используемых интерфейсов скрипта.

Для того чтобы функция попала в это описание, достаточно, добавить комментарий перед названием функции, комментарий должен быть в начале строки и за ним должен следовать пробел, а если вы хотите убрать функцию из описания, то достаточно убрать этот пробел.

Комментарии внутри bash функций уже в help не попадут по определению, так как они идут не вначале строки, а сдвинуты хотя бы на 4 пробела, так как форматирование в скриптах я надеюсь еще никто не отменял.

Как это работает:

* realpath — преобразует относительный путь в абсолютный;
* grep -A 1 "^# " — ищет строки, начинающиеся с "# " и захватывает следующую строку;
* sed 's/--//g' — удаляет символы --, которые добавляются grep.

Есть конечно и недостатки: для больших скриптов, это может выглядеть громоздко и если функций много, то это не всегда оправдано.

Из достоинств: названия функций будут всегда актуальными и нужно еще постараться придумать емкое описание функции в одну строку, а если не получается сформулировать в одну, то может быть задуматься, а нужна ли она вообще такая функция?


## Развертывание YoctoDemoMinimal образа из Yocto коробки

Для работы с Yocto я подготовил хороший пример - конфигурацию, для сборки минимального Yocto образа
для платы Raspberry Pi 4, по нажатию этой кнопки выполняется следующий код:

```bash
example_yocto_demo_minimal_rpi4() {
  local proj_demo="${YO_DIR_PROJECTS}/yocto-demo-minimal"
  mkdir -p "${proj_demo}"
  cd ${proj_demo}
  repo init -u https://github.com/berserktv/bs-manifest -m raspberry/scarthgap/yocto-demo-minimal.xml
  repo sync

  # первый запуск конфигурации, создание каталога build
  echo "exit" | ./shell.sh

  # скрипт для запуска VSCode
  echo "#!/bin/bash" > start-vscode.sh
  echo "cd sources/meta-raspberrypi" >> start-vscode.sh
  echo "code ." >> start-vscode.sh
  chmod u+x start-vscode.sh

  # запуск нового экземпляра VSCode
  cd sources/meta-raspberrypi
  git clone https://github.com/berserktv/vscode-yocto-helper.git .vscode
  # rm -fr .vscode/.git
  code .
}
```

Таким образом настройка плагина с кнопками копируется в тот каталог с исходным кодом одного из слоев Yocto Project, который я хотел бы выбрать в качестве основного каталога разработки, в примере у меня это BSP слой для поддержки платы Raspberry Pi 4 => "meta-raspberrypi".

Затем запускается второй экземпляр VSCode c этой новой конфигурацией и там уже кнопки сборки окажутся в привычном для себя окружении, и можно собрать образ "core-image-minimal" из Yocto коробки.


## Выписываем Buster Slim(а) для крутой разборке в Докере

Далее я буду разбираться с загрузкой собранного core-image-minimal для платы Raspberry Pi 4. Следующая функция которая мне ну просто необходима это загрузка Raspberry Pi 4 по сети. И для этого нужен только сетевой кабель, очень удобно. Собрали какую то версию дистрибутива, загрузили по сети, что то проверили, снова загрузили и т.д.

Предполагается, что по одному интерфейсу на хост компьютере, например Wifi подключен интернет, а второй сетевой интерфейс свободен, вот его мы и будем напрямую соединять кабелем с сетевым интерфейсом Raspberry Pi 4.

Если ничего не менять в Yocto конфигурации и слое meta-raspberrypi, то собирается архивный wic образ `bz2 =>  core-image-minimal-raspberrypi4-64.rootfs.wic.bz2`

Если его распаковать, то можно посмотреть структуру командой:

`fdisk -l core-image-minimal-raspberrypi4-64.rootfs.wic`

Это стандартный RAW образ, который содержит в своем составе таблицу разделов состоящей из двух логических дисков:

- загрузочный раздел fat32;
- корневой rootfs раздел в формате ext4.

для того, чтобы образ подмонтировать, я написал следующий код:

```bash
mount_raw_image() {
  if [[ -z "${IMAGE_DIR}" || -z "${IMAGE_NAME}" || -z "${MOUNT_DIR}" ]]; then
      echo "Ошибка: Установите переменные окружения IMAGE_DIR, IMAGE_NAME и MOUNT_DIR" >&2
      return 1
  fi

  local image_file="${IMAGE_DIR}/${IMAGE_NAME}"
  if [ ! -f "${image_file}" ]; then
      echo "Ошибка: Файл образа ${image_file} не найден" >&2
      return 2
  fi

  local loop_dev=$(losetup -j "${image_file}" | awk -F: '{print $1}')
  if [ -z "${loop_dev}" ]; then
      loop_dev=$(sudo losetup -f --show -P "${image_file}")
      if [[ $? -ne 0 ]]; then echo "Ошибка: Не удалось создать loop-устройство" >&2; return 3; fi
      echo "Создано новое loop-устройство: ${loop_dev}"
  else
      echo "Используется существующее loop-устройство: ${loop_dev}"
  fi

  local uid=$(id -u)
  local gid=$(id -g)
  get_mount_base
  mkdir -p ${MOUNT_BASE_DIR}

  for part_num in {1..4}; do
      local partition="${loop_dev}p${part_num}"
      if [[ -b "${partition}" ]]; then
          local mount_point="${MOUNT_BASE_DIR}/part${part_num}"
          if mountpoint -q "${mount_point}"; then
              echo "Раздел ${part_num} уже смонтирован в ${mount_point}, пропускаем..."
              continue
          fi

          mkdir -p "${mount_point}"
          local fs_type=$(sudo blkid -o value -s TYPE "${partition}")
          case "${fs_type}" in
              vfat)
                  sudo mount -o rw,uid=${uid},gid=${gid} "${partition}" "${mount_point}" ;;
              *)
                  sudo mount -o rw "${partition}" "${mount_point}" ;;
          esac

          if [[ $? -eq 0 ]]; then echo "Раздел ${part_num} смонтирован в ${mount_point}";
          else echo "Ошибка при монтировании раздела ${part_num}" >&2; fi
      fi
  done
}
```

Здесь я использую механизм ядра, который позволяет обращаться к обычным файлам как к блочным устройствам, Loop устройства как бы "замыкают" файл в виртуальный диск и система работает с ним так же, как и с реальным устройством.

И основная утилита в Linux для этого, это losetup. Для разных типов файловых систем могут использоваться немного разные параметры, например для fat32 не получиться редактировать файлы от имени обычного пользователя без uid/gid, а мне это нужно, очень нужно.

Для работы функции ей нужно задать три параметра, вернее три переменные окружения:

`IMAGE_NAME` - название образа
`IMAGE_DIR`  - каталог в котором находится файл образа
`MOUNT_DIR`  - каталог в который файл образа будет примонтирован

здесь дополнительно используется функция `get_mount_base`:

```lua
MOUNT_BASE_DIR=""
IMAGE_NAME_SHORT=""
get_mount_base() {
    local name_without_ext="${IMAGE_NAME%.*}"
    MOUNT_BASE_DIR="${MOUNT_DIR}/${name_without_ext}"
    IMAGE_NAME_SHORT="${name_without_ext}"
}
```

которая по названию образа `IMAGE_NAME`, позволяет определить базовую точку монтирования в каталоге `MOUNT_DIR`, так как образ составной и может содержать N разделов, каждый из который в свою очередь монтируется под именами part1, part2 и т.д. это переход к однотипному именованию, для любого raw образа.

Здесь еще устанавливается переменная сокращенного названия образа:

например из:
core-image-minimal-raspberrypi4-64.rootfs.wic
получиться => core-image-minimal-raspberrypi4-64.rootfs

для размонтирования, я использую umount_raw_image с теме же переменными окружения:

```lua
umount_raw_image() {
  if [[ -z "${IMAGE_DIR}" || -z "${IMAGE_NAME}" || -z "${MOUNT_DIR}" ]]; then
      echo "Ошибка: Установите переменные окружения IMAGE_DIR, IMAGE_NAME и MOUNT_DIR" >&2; return 1
  fi

  get_mount_base
  local name_without_ext="${IMAGE_NAME%.*}"
  if [ ! -d ${MOUNT_BASE_DIR} ]; then
      echo "Ошибка: Директория ${MOUNT_BASE_DIR} не найдена, выход..." >&2; return 2
  fi

  local mounted_parts=("${MOUNT_BASE_DIR}"/part*)
  if [[ -e "${mounted_parts[0]}" ]]; then
      for mount_point in "${mounted_parts[@]}"; do
          if mountpoint -q "${mount_point}"; then
              sudo umount "${mount_point}"
              if [[ $? -eq 0 ]]; then echo "Размонтирование ${mount_point} выполнено успешно"
              else echo "Ошибка: Не удалось размонтировать ${mount_point}" >&2; fi
          else
              echo "Предупреждение: ${mount_point} не смонтирован" >&2
          fi
      done
  else
      echo "Не найдено смонтированных разделов в ${MOUNT_DIR}/${name_without_ext}"
  fi

  local image_file="${IMAGE_DIR}/${IMAGE_NAME}"
  if [[ -f "${image_file}" ]]; then
      local loop_devices
      loop_devices=$(losetup -j "${image_file}" | awk -F: '{print $1}')
      for loop_dev in ${loop_devices}; do
          sudo losetup -d "${loop_dev}"
          if [[ $? -eq 0 ]]; then echo "Loop-устройство ${loop_dev} успешно отсоединено"
          else echo "Ошибка: Не удалось отсоединить loop-устройство ${loop_dev}" >&2; fi
      done
  else
      echo "Предупреждение: Файл образа ${image_file} не найден, очистка loop-устройств пропущена" >&2
  fi
}
```

С функциями `mount_raw_image()` и `umount_raw_image()` я могу приступить к загрузке по сети.

Для этого буду использовать Buster Slim докер - "debian:buster-slim":

## Настройка DHCP, TFTP и NFS сервера

```dart
docker
└── dhcp_tftp_nfs
    ├── Dockerfile
    ├── entrypoint.sh
    ├── etc
    │   ├── default
    │   │   ├── isc-dhcp-server
    │   │   └── nfs-kernel-server
    │   ├── dhcp
    │   │   └── dhcpd.conf
    │   ├── exports
    │   └── network
    │       └── interfaces
    ├── Makefile
    ├── reconfig_net.sh
    └── rpi
        ├── cmdline.txt
        └── enable_uart.txt
```

Основной файл докера:

```dart
FROM debian:buster-slim

ENV DEBIAN_FRONTEND noninteractive
ENV DEBCONF_NONINTERACTIVE_SEEN true

RUN apt-get update && \
    apt-get install --no-install-recommends -y \
        isc-dhcp-server \
        tftpd-hpa \
        rpcbind \
        nfs-kernel-server && \
    # Clean rootfs
    apt-get clean all && \
    apt-get autoremove -y && \
    apt-get purge && \
    rm -rf /var/lib/{apt,dpkg,cache,log} && \
    # Configure DHCP
    touch /var/lib/dhcp/dhcpd.leases && \
    # Configure rpcbind
    mkdir -p /run/sendsigs.omit.d /etc/modprobe.d /var/lib/nfs && \
    touch /run/sendsigs.omit.d/rpcbind && \
    touch /var/lib/nfs/state

WORKDIR /

COPY entrypoint.sh /entrypoint.sh
# Set correct entrypoint permission
RUN chmod u+x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
```

Здесь устанавливаются три основных сервера, нужные мне для сетевой загрузки: DHCP, TFTP и NFS.

Скрипт для запуска `entrypoint.sh` выглядит так:

```bash
#!/bin/sh

# перехват сигнала остановки процесса по Ctrl+C или docker stop
# и вызов функции stop для корректного завершения сервисов
trap "stop; exit 0;" TERM INT

stop()
{
    echo "Получен SIGTERM, завершаем процессы..."
    echo "Остановка NFS..."
    exportfs -uav
    service nfs-kernel-server stop
    echo "Остановка TFTP..."
    service tftpd-hpa stop
    echo "Остановка DHCP..."
    service isc-dhcp-server stop

    exit 0
}

start()
{
    echo "Запуск сервисов..."
    echo "Инициализация DHCP..."
    service rsyslog start
    service isc-dhcp-server start
    echo "Инициализация TFTP..."
    service tftpd-hpa start
    echo "Инициализация NFS..."
    service rpcbind start
    service nfs-common start
    service nfs-kernel-server start
    exportfs -rva

    echo "Сервисы запущены..."
    while true; do sleep 1; done

    exit 0
}

start
```

для запуска Buster Slim служит Makefile:

```bash
IMAGE=dhcp_tftp_nfs
DOCKER_TAG=buster-slim
DOCKER_NETWORK="--network=host"
TFTP_DIR=/tmp/docker/tftp
NFS_DIR=/tmp/docker/nfs

# Host network config =>
HOST_NET_IFACE=""
IP_ADDR="10.0.7.1"
IP_SUBNET="10.0.7.0"
IP_MASK="255.255.255.0"
IP_MASK2="24"
IP_RANGE="range 10.0.7.100 10.0.7.200"

run:
    sudo ip addr flush dev $(HOST_NET_IFACE)
    sudo ip addr add $(IP_ADDR)/$(IP_MASK) dev $(HOST_NET_IFACE)
    sudo ip link set $(HOST_NET_IFACE) up

    sudo modprobe nfsd
    if ps aux | grep -q /sbin/rpcbind; then sudo systemctl stop rpcbind.socket; sudo systemctl stop rpcbind; fi

    docker run --rm -ti --privileged \
    ${DOCKER_NETWORK} \
    -v ${TFTP_DIR}:/srv/tftp \
    -v ${NFS_DIR}:/nfs \
    -v ${PWD}/etc/exports:/etc/exports \
    -v ${PWD}/etc/default/nfs-kernel-server:/etc/default/nfs-kernel-server \
    -v ${PWD}/etc/default/isc-dhcp-server:/etc/default/isc-dhcp-server \
    -v ${PWD}/etc/dhcp/dhcpd.conf:/etc/dhcp/dhcpd.conf \
    -v ${PWD}/etc/network/interfaces:/etc/network/interfaces \
    ${IMAGE}:${DOCKER_TAG}

build:
    docker build --rm -t ${IMAGE}:${DOCKER_TAG} .

rebuild:
    docker build --rm --no-cache -t ${IMAGE}:${DOCKER_TAG} .

install:
    sudo apt-get update
    sudo apt-get install -y docker.io

clean-all-container:
    sudo docker rm $(docker ps -qa)

.PHONY: run build clean-all-container
```

Здесь докер запускается в привилегированном режиме и в процессе запуска он пробрасывает несколько основных конфигурационных файлов для DHCP и NFS.

В самом простом случае, для запуска вы можете настроить следующие файлы для конфигурации сетевого интерфейса в докере:

```lua
#######################################
# конфигурация /etc/network/interfaces
#####################################
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet static
address 10.0.7.1
netmask 255.255.255.0
```

Так как докер Buster Slim запускается в сетевом режиме хоста, параметр "--network=host", то и название сетевого интерфейса обязательно должно быть как на хосте, здесь это для примера "eth0".

Конфигурация DHCP сервера в докере:

```lua
############################################
# конфигурация /etc/default/isc-dhcp-server
##########################################
DHCPDv4_CONF=/etc/dhcp/dhcpd.conf
DHCPDv4_PID=/var/run/dhcpd.pid
INTERFACESv4="eth0"

####################################
# конфигурация /etc/dhcp/dhcpd.conf
##################################
option domain-name "example.org";
option domain-name-servers ns1.example.org;
default-lease-time 600;
max-lease-time 7200;
ddns-update-style none;

subnet 10.0.7.0 netmask 255.255.255.0 {
    range 10.0.7.100 10.0.7.200;
    option routers 10.0.7.1;
    option subnet-mask 255.255.255.0;
    option tftp-server-name "10.0.7.1";
    option bootfile-name "bootcode.bin";
}
```

Для DHCP в первую очередь необходимо указать слушающий сетевой интерфейс, на котором все и работает, это тоже имя, что и на хосте, далее указывается диапазон пула динамических адресов, адрес шлюза, маска сети, адрес TFTP сервера, который раздает и главное, это первичный загрузчик для сетевой загрузки "bootcode.bin" (здесь у меня есть вопросы называть ли его первичным или вторичным, но не в этом суть).

Здесь главное, что если вы загружаете плату Raspberry Pi 4 по сети, то этот загрузчик обязательно должен быть в корне TFTP сервера, иначе никто ни к кому по сети не приедет.

По умолчанию, плата Raspberry Pi 4 настроена на загрузку с microSD карты памяти, далее приоритет загрузки уменьшается возможно это USB, и далее идет загрузка с использованием сетевой карты.

Вы можете это легко проверить, подключив к плате монитор по HDMI интерфейсу и вытащив SD карту памяти подайте на нее питание. Так как не SD карты, не USB диска не подключено, то должна запуститься сетевая загрузка, это вы увидите на экране монитора, по красивой заставке с надписью о запуске «сетевой загрузки».

Если что то не так, то можно обновить переменную в EEPROM отвечающую за порядок загрузки Raspberry Pi 4:

```lua
################################
# на Desktop компьютере
################################
# установите Raspberry Pi Imager
sudo apt install rpi-imager

# вставьте в картридер microSD карту для записи обновления EEPROM
# с помощью запуска программы rpi-imager
rpi-imager

# Выберите устанавливаемую операционную систему (CHOOSE OS)
=> Misc utility images (Bootloader EEPROM configuration)
=> Bootloader (Pi 4 family)

# Выбирайте один из трех образов, с разными приоритетами загрузки
# советую выбирать приоритет загрузки SD => USB => network
# т.е. загрузка по сети с наименьшим приоритетом

# Подождите окончания записи, и если все ОК,
# подключите SD карту памяти к Raspberry Pi 4
# Если вы подключите отладочный USB-uart к GPIO то сможете увидеть процесс обновления
sudo picocom --baud 115200 /dev/ttyUSB0

# после подачи питания на плату по UARТ хотя бы можно понять что происходит, например:
...
Reading EEPROM: 524288
Writing EEPROM
......................................................................................+....+
Verify BOOT EEPROM
Reading EEPROM: 524288
BOOT-EEPROM: UPDATED

# если UART(A) нет то следите за светодиодами, они подскажут
```


Конфигурация NFS сервера в докере:

```lua
##############################################
# конфигурация /etc/default/nfs-kernel-server
############################################
# Number of servers to start up
RPCNFSDCOUNT=8
# Runtime priority of server (see nice(1))
RPCNFSDPRIORITY=0
# Options for rpc.mountd. (rpcinfo -p)
RPCMOUNTDOPTS="--nfs-version 4.2 --manage-gids"
NEED_SVCGSSD=""
# Options for rpc.svcgssd.
RPCSVCGSSDOPTS=""
# Options for rpc.nfsd. (cat /proc/fs/nfsd/versions)
RPCNFSDOPTS="--nfs-version 4.2"

###########################
# конфигурация /etc/export
#########################
/nfs  *(rw,fsid=0,sync,no_subtree_check,no_root_squash,no_all_squash,crossmnt)
```

Здесь я во возможности включаю версию 4, но остальные версии то же должны работать.

Конфигурация NFS экспорта:

* `rw` разрешение чтения и записи;
* `fsid=0` указывает, что это корневой экспорт для NFSv4. В NFSv4 клиенты монтируют "виртуальную"
  корневую файловую систему (например, /), а все остальные экспорты становятся её поддиректориями;
* `sync` требует синхронной записи данных на диск перед подтверждением операции,
  это гарантия целостности данных, ну и медлительности конечно;
* `no_subtree_check` отключить проверку нахождения файла внутри экспортированной директории при каждом запросе;
* `no_root_squash` не преобразовывать права пользователя root с клиента в анонимного пользователя,
  дает клиентам полный root-доступ к файлам на сервере, но так как у нас корневая rootfs полноценной ОС,
  он нам нужен, иначе наша запускаемая ОС нормально работать не будет;
* `no_all_squash` не преобразовывать права всех пользователей в анонимного пользователя,
  cохраняет оригинальные UID/GID пользователей клиента на сервере, тоже нужен, см. предыдущий пункт.

Еще бы хотел отметить что именно с NFS сервером, у меня наблюдались некоторые проблемы:

- Во первых он может работать только единолично, т.е. если запустить два таких докера, то второй
  будет мешать первому, исключаем это тем, что запускаем этот докер
  без фонового режима (убираю make run_detach),
  и перед запуском всегда останавливаю все найденные докеры с таким названием;
- Во вторых в режиме network=host докер будет использовать модуль хостового ядра, нужен "modprobe nfsd"
  перед запуском докера;
- В третьих перед запуском докера, нужно выключить rpcbind сервис на хосте, он тоже мешает докеру
  так что если ваш Desktop компьютер не может отказаться от `rpcbind`, то загрузку можно и отложить,
  имейте это ввиду.

```cmake
if ps aux | grep -q /sbin/rpcbind; then
    sudo systemctl stop rpcbind.socket;
    sudo systemctl stop rpcbind;
fi
```

Еще раз вернемся к Makefile Buster Slim(а):

```lua
...
TFTP_DIR=/tmp/docker/tftp
NFS_DIR=/tmp/docker/nfs

# Host network config =>
HOST_NET_IFACE=""
IP_ADDR="10.0.7.1"
IP_SUBNET="10.0.7.0"
IP_MASK="255.255.255.0"
IP_MASK2="24"
IP_RANGE="range 10.0.7.100 10.0.7.200"
```


В переменной `HOST_NET_IFACE` прописывается название того же сетевого интерфейса хоста, который указан в `/etc/network/interfaces` и `/etc/default/isc-dhcp-server`. 

При работе с докером у меня вначале вызывается shell скрипт `docker/dhcp_tftp_nfs/reconfig_net.sh` для автоматической настройки `/etc/network/interfaces` и `/etc/default/isc-dhcp-server`, а также некоторых других файлов.

И эта перенастройка выполняется в том случае, если
переменная Makefile:  HOST_NET_IFACE="" пустая.

После перенастройки, скрипт меняет эту переменную, вносит название найденного локального сетевого интерфейса  (например HOST_NET_IFACE="eth0"), фактически настройка выполняется только один раз. 

Скрипт reconfig_net.sh для настройки использует переменные из `Makefile`:
`IP_ADDR` `IP_SUBNET` `IP_MASK IP_RANGE`, так что можно попробовать и свою локальную конфигурацию добавить. Но здесь есть одна проблема, я определяю локальный сетевой интерфейс хост компьютера так:

```lua
ip link show | awk -F: '$0 !~ "lo|vir|docker|veth|br|wl" {print $2; getline; print $2}' | tr -d ' ' | head -n 1

# и если вдруг у вас два локальных сетевых интерфейса,
# то это может не сработать
# и вам будет нужно настраивать
# приведенные выше файлы самостоятельно

# еще есть вопрос
# к переменной IP_TFTP="10.0.7.1" в func.sh
# сейчас она статическая
# и нужно в случае изменения IP_ADDR в Makefile
# также и ее изменить.
```

Также в Makefile указаны основные, базовые каталоги `TFTP_DIR` и `NFS_DIR`, которые всегда прокидываются в докер при старте, это может быть например символическая ссылка на каталог, который представляет собой точку монтирования, полученную в результате работы функции `mount_raw_image`.

Для core-image-minimal-raspberrypi4-64.rootfs.wic например:
ссылка /tmp/docker/tftp => core-image-minimal-raspberrypi4-64.rootfs/part1
ссылка /tmp/docker/nfs  => core-image-minimal-raspberrypi4-64.rootfs/part2

Загрузочный раздел отдаем в распоряжение TFTP, а корневой rootfs раздел отдаем NFS серверу.

На что же это похоже: Buster Slim не подвел, у нас намечается **«Большой распил образов»**.

## Распил образов

Итак чем же хорош распил образов, а тем что вам становиться все равно, что вообще грузить, хочешь «Raspbian», хочешь «Бубунту», хочешь «mcom03» (но это исключительно для друзей Элвиса), и далее мы с вами что то из этого перечня загрузим, добавив несколько десятков строк bash кода и корректируя докер.

Докер Buster Slim в данном случае творит чудеса. Это крутая разборка. 

Еще интересно что все равно не только что грузить, но и куда грузить, т.е. выбрасываем Raspberry Pi 4, цепляем сетевым кабелем соседний компьютер (если у него есть конечно поддержка сетевой pxe загрузки), выбираем загрузку с сетевой карты в BIOS, добавляем еще секцию bash кода и грузим этот компьютер.

Задача: загрузить все что есть в прямой видимости.

В некоторых случаях, когда образ загружен он будет считать что работает нативно, для Raspbian например физически образ это один файл содержащий таблицу разделов и логические диски, после монтирования через losetup образ распиливается на несколько логических дисков (обычно два), и каждая из точек монтирования будет вести себя так, как позволяет ее файловая система, в ext4 например можно писать, в ISO только читать и т.д.

Свободного места в образе обычно не много, так как это важный критерий увеличения размера файла образа, но это можно исправить для долгосрочного использования одного и того же образа, ведь хороший образ должен всегда быть под рукой.

## Загрузка core-image-minimal (wic) образа на Raspberry Pi 4 по сети

Итак код верхнего уровня, который запускает загрузку по сети:

```lua
start_netboot_rpi4() {
    DOCKER_DIR='docker/dhcp_tftp_nfs'
    stop_docker "dhcp_tftp_nfs:buster-slim"
    mount_raw_rpi4 && start_session_docker
}
```

далее функция mount_raw_rpi4:

```lua
mount_raw_rpi4() {
    if ! set_env_raw_rpi4; then return 1; fi

    mount_raw_image
    change_bootloader_name_in_dhcp "raspberry"
    raspberry_pi4_cmdline_for_nfs "${MOUNT_BASE_DIR}/part1"
    create_mount_point_for_docker "tftp" "${MOUNT_BASE_DIR}/part1"
    create_mount_point_for_docker "nfs" "${MOUNT_BASE_DIR}/part2"
    # problem with video adapter: used fake kms (old driver)
    sed -i "s|^dtoverlay=vc4-kms-v3d|#&\n dtoverlay=vc4-fkms-v3d|g" "${MOUNT_BASE_DIR}/part1/config.txt"
}
```

Здесь вначале я монтирую выбранный образ через losetup и после того, как все подмонтировалось:
- меняю название загрузчика для DHCP сервера => на
  option bootfile-name "bootcode.bin";
- меняю параметры ядра для сетевой загрузки в штатном cmdline.txt файле первого,
  загрузочного раздела образа => на
  `console=serial0,115200 console=tty1 root=/dev/nfs nfsroot=10.0.7.1:/nfs,hard,nolock,vers=3 rw ip=dhcp rootwait`
- прокидываю правильные точки монтирования в наш TFTP и NFS сервер;
- и исправляю проблему с которой столкнулся, при выводе изображения, включаю более старый видео драйвер
  (сильно не разбирался из за чего, но слой meta-raspberry беру как есть, ничего не меняя)

Что хотелось бы отметить:

Список файлов которые запрашивает наш проприетарный **bootcode.bin** похоже жестко в нем зашиты, у меня не получилось изменить имя файла ядра, меняя штатный **config.txt** на первом разделе:

```lua
kernel=название_файла_ядра
```

Есть еще привязка к каталогу со стандартным именем для конкретной платы в корне tftp
`<serial_number>/config.txt`
но мне это не подходит, мне нужно загрузить любую плату, поэтому можно попробовать просто
подсунуть `bootcode.bin` то название, которое он хочет, создав копию ядра (на fat ссылки не работают) или
переименовав то ядро, которое есть на первом разделе, в ожидаемое загрузчиком, если места там впритык.

Для `YoctoDemoMinimal` (ветка scarthgap), этого делать не пришлось, название оказалось уже правильным.

Чтобы узнать что нужно `bootcode.bin` можно посмотреть протокол запросов на хосте:

```lua
sudo tcpdump -i eth0 -vvv -n "(port 67 or port 68) or (udp port 69)"
```

также не забудьте изменить название вашего сетевого интерфейса хоста

Разберем параметры:

* console=serial0,115200 console=tty1: включает вывод на последовательный порт (serial0) и консоль (tty1);
* root=/dev/nfs: указывает, что корневая файловая система будет загружена по NFS;
* nfsroot=10.0.7.1:/nfs,hard,nolock: 
  - IP-адрес NFS-сервера и экспортируемый каталог;
  - hard: — указывает, что операции должны быть повторены в случае сбоя;
  - nolock — отключает использование блокировок (рекомендуется для NFSv4);
* rw монтирует корневую файловую систему с правами на чтение и запись;
* ip=dhcp указывает, что IP-адрес должен быть получен через DHCP;
* rootwait ожидает, пока корневая файловая система не будет готова.


В самом начале функции `mount_raw_rpi41 идет инициализация переменных среды для выбора загружаемого образа:

```lua
set_env_raw_rpi4() {
  if find_name_image && select_yocto_image; then
      IMAGE_NAME="${IMAGE_SEL}"
      IMAGE_DIR="${YO_DIR_IMAGE}/${YO_M}"
      MOUNT_DIR="${IMAGE_DIR}/tmp_mount"
      if check_bz2_archive "${IMAGE_SEL}"; then
          mkdir -p "${MOUNT_DIR}"
          IMAGE_NAME="${IMAGE_SEL%.bz2}"
          extract_bz_archive "${IMAGE_DIR}/${IMAGE_SEL}" "${MOUNT_DIR}" "${IMAGE_NAME}"
          IMAGE_DIR="${MOUNT_DIR}"
      fi
      return 0
  fi
  return 1
}
```

Функция `find_name_image` ищет есть ли вообще хоть какие либо подходящие образы, если они есть, вам будет предложен список из N пунктов в консоли, где вы можете ввести номер от 1 до N, если вы выбрали архивный образ, он будет распакован и будут настроены переменные среды на возможную загрузку этого образа через mount_raw_image.

У меня есть еще функция, которая возвращает файлы образа `config.txt` и `cmdline.txt` в первоначальное состояние, вдруг вы захотите этот образ прошить на SD карту командой dd, после каких нибудь манипуляций, всякое бывает.

```lua
restore_image_rpi4() {
  if ! set_env_raw_rpi4; then return 1; fi

  mount_raw_image
  local mount_dir="${MOUNT_BASE_DIR}/part1"
  for file in config.txt cmdline.txt; do
      restore_orig "${mount_dir}/${file}"
  done
  umount_raw_image
}
```

Перед тем, как что то восстанавливать, не забудьте, что на загруженном образе лучше набрать poweroff и подождать, пока корневая файловая система NFS корректно отмонтируется.

После выключения Raspberry Pi 4, можно корректно отключать и все точки монтирования. Но еще не забудьте выключить сам докер, он запускается в терминале VSCode и ждет завершения по Ctrl+C или docker stop hash_container, это надо учитывать.

Далее вызываем `restore_image_rpi4` и если все Оk, можно попробовать образ записать. Если образ архивный, то для функции `sdcard_deploy` вам еще нужно будет переписать файл вручную из tmp_mount в каталог с образами по умолчанию (не предусмотрел пока).

Заодно проверите, есть ли проблема `dtoverlay=vc4-kms-v3d` (или это только у меня такое). Если проблема есть, то вам понадобиться отладочный UART, видео нет, ничего не видно, или же вы можете сразу на SD карте подкорректировать **`config.txt`** после копирования raw образа командой dd.


## Сетевая загрузка Raspbian для платы Raspberry Pi 4

Итак код верхнего уровня, загрузка по сети для Raspbian:

```lua
start_netboot_raspios() {
    set_env_raw_raspios
    stop_docker "dhcp_tftp_nfs:buster-slim"
    mount_raw_raspios && start_session_docker
}
```

далее:

```lua
set_env_raw_raspios() {
  IMAGE_DIR="${DOWNLOAD_RASPIOS}"
  IMAGE_NAME="2024-11-19-raspios-bookworm-arm64.img"
  MOUNT_DIR="${DOWNLOAD_RASPIOS}/tmp_mount"
  DOCKER_DIR='docker/dhcp_tftp_nfs'
}

mount_raw_raspios() {
  download_raspios || return 1
  mount_raw_image || return 2
  add_cmdline_for_nfs_raspios
  disable_partuuid_fstab_for_raspios
  docker_dhcp_tftp_reconfig_net
  change_bootloader_name_in_dhcp "raspberry"
  create_mount_point_for_docker "tftp" "${MOUNT_BASE_DIR}/part1"
  create_mount_point_for_docker "nfs" "${MOUNT_BASE_DIR}/part2"
}
```

Здесь меняю на загрузочном разделе fat штатный `cmdline.txt` на такой:

```lua
console=serial0,115200 console=tty1 root=/dev/nfs nfsroot=10.0.7.1:/nfs,hard,nolock,vers=3 rw ip=dhcp rootwait
```

И еще, для того, чтобы все прошло гладко, нужно модифицировать штатный `/etc/fstab` в образе Raspbian:
(иначе не полетит, проверять будет, пытаться и проверять и долго так)

```lua
disable_partuuid_fstab_for_raspios() {
  local fstab_file="${MOUNT_BASE_DIR}/part2/etc/fstab"
  [[ -f "${fstab_file}" ]] || return 1

  if cat "${fstab_file}" | grep -q "^PARTUUID="; then
      echo "Disable the PARTUUID entries in ${fstab_file}"
      echo "This is an NFS root filesystem for RaspiOS, and the root password is required."
      sudo sed -i "s|^PARTUUID=|#PARTUUID=|g" "${fstab_file}"
  fi
}

restore_partuuid_fstab_for_raspios() {
  local fstab_file="${MOUNT_BASE_DIR}/part2/etc/fstab"
  [[ -f "${fstab_file}" ]] || return 1

  if cat "${fstab_file}" | grep -q "^#PARTUUID="; then
      echo "Need to restore the PARTUUID entries in ${fstab_file}"
      echo "This is an NFS root filesystem for RaspiOS, and the root password is required."
      sudo sed -i "s|^#PARTUUID=|PARTUUID=|g" "${fstab_file}"
  fi
}
```

А мы его с вами обманем и диски `PARTUUID=` закоментируем под root(ом), а потом если нужно, снова включим,
оставив образ для возможности прошить на SD карту командой dd:

```lua
restore_image_raspios() {
    set_env_raw_raspios
    mount_raw_image
    local mount_dir="${MOUNT_BASE_DIR}/part1"
    for file in config.txt cmdline.txt; do
        restore_orig "${mount_dir}/${file}"
    done
    restore_partuuid_fstab_for_raspios
    umount_raw_image
}
```

Примечание: в config.txt еще включается отладка по UART, его можно к GPIO пинам подцепить, поэтому он тоже восстанавливается как был у `Raspbian`(RaspiOS).


## Автоматический анализ сборочных Yocto логов с помощью нейронной сети Deepseek

Следующей функцией которая мне еще нужна, является функция ускоренного анализа каких либо сборочных логов и исправления Yocto ошибок, что бы совсем быстро и конечно в этом случае очень пригодится какая нибудь нейронная сеть, пусть она по возможности дает советы по исправлению ошибок, в идеале мне нужно лог сборки напрямую перенаправить на вход нейронной сети, без посредников.

А то сидишь копируешь одну простыню ошибок из одной консоли, вставляешь ее в окно браузера куда нибудь на chat.deepseek.com это жутко долго, это очень утомительно, итак приступим:

Установка и запуск DeepSeek через Ollama оказался на редкость простым, тот же Stable Diffusion помню пол дня устанавливал, то это не то, то другое, а здесь просто магия какая то, полностью скрытая от пользователя и это реально круто.

```lua
# модель весит 4.9 Гб и сама ollama ~3 Гб
DEEPSEEK_MODEL="deepseek-r1:8b"
install_deepseek() {
    curl -fsSL https://ollama.com/install.sh | sh
    ollama serve
    ollama run ${DEEPSEEK_MODEL}
}
```

В качестве модели я взял не очень требовательную к ресурсам "deepseek-r1:8b" на 4.9 Гб, размер всей установки потянул примерно на 8Гб свободного места на диске и самое интересное что она как то более дружелюбно относится к русском языку, например более тяжелая версия deepseek-r1:14b ведет себя неприлично, ты ее спрашивает на русском, а она тебе талдычит по английски, иногда переходя на русский, а эта так сразу по русски.

На мой взгляд локальную deepseek-r1 еще можно использовать как переводчик, очень удобно, а за хорошим советом все же придется идти на chat.deepseek.com, ну или куда вы там ходите.

Команда curl используется для скачивания скрипта установки с указанного URL:

* опция -f включает "fail silently" (тихую неудачу);
* опция -s делает запрос без прогресс-бара, а `-S` показывает ошибки, если что-то идет не так;
* опция -L (опция "follow redirects") используется для автоматического перенаправления
  запроса на сервер к новому URL, если это будет необходимо.
  затем результат (`|`) передается в `sh`, который выполняет скачанный скрипт локально.

Далее запускается ollama сервер и запускается выбранная модель. При первом запуске модель, загружается на локальный компьютер.

И сразу приведу код для удаления ollama и всех ее «моделей», посмотрели и хватит:

```lua
unistall_ollama() {
    #Remove the ollama service:
    sudo systemctl stop ollama
    sudo systemctl disable ollama
    sudo rm /etc/systemd/system/ollama.service
    #Remove the ollama binary from your bin directory:
    sudo rm $(which ollama)
    #Remove the downloaded models and Ollama service user and group:
    sudo rm -r /usr/share/ollama
    sudo userdel ollama
    sudo groupdel ollama
    #Remove installed libraries:
    sudo rm -rf /usr/local/lib/ollama
}
```

Запуск оllama, в консоли, который можно повесить на нажатие кнопки:

```lua
run_deepseek() {
    ollama run ${DEEPSEEK_MODEL}
}
```

А вот так в моем понимании может выглядеть анализ Yocto логов в Deepseek, в выходные надеюсь проверю, пока не успеваю, ну как обычно. Нужно или статью писать или код проверять, одновременно не получается. Тут главное, чтобы логи были не очень большими,  если вдруг заметили ошибку определенную, то можно передать. На больших логах точно нейросеть завалите, буфер какой нибудь переполниться и все (как по мне).

```lua
yocto_analyze_deepseek() {
  local cmd_runs="$1"
  DOCKER_DIR="docker/ubuntu_22_04"
  CONTAINER_NAME="ubuntu_22_04"
  cmd_init="cd /mnt/data; MACHINE=$YO_M source ./setup-environment build"
  start_cmd_docker "${cmd_init}; ${cmd_runs}" | ollama run ${DEEPSEEK_MODEL} 'проведи анализ логов'
}
```


## Побочный эффект сборки, загрузка ISO дистрибутива Ubuntu по сети

Итак код верхнего уровня, который запускает загрузку по сети:

```lua
start_ubuntu_22_04() {
  IMAGE_NAME="ubuntu-22.04.1-desktop-amd64.iso"
  IMAGE_UBUNTU_URL="http://releases.ubuntu.com/22.04.2"
  DOCKER_DIR='docker/dhcp_tftp_nfs'
  stop_docker "dhcp_tftp_nfs:buster-slim"
  mount_raw_ubuntu && start_session_docker
}
```
Запускается монтирование `mount_raw_ubuntu` ISO образа и в случае успеха сессия докера в консоли:

```lua
mount_raw_ubuntu() {
  IMAGE_DIR="${DOWNLOAD_UBUNTU}"
  MOUNT_DIR="${DOWNLOAD_UBUNTU}/tmp_mount"
  download_ubuntu || return 1
  download_netboot_ubuntu || return 2
  mount_raw_image || return 3

  local pxe_default="${DOWNLOAD_UBUNTU}/netboot/pxelinux.cfg/default"
  local kernel="${MOUNT_BASE_DIR}/part1/casper/vmlinuz"
  local initrd="${MOUNT_BASE_DIR}/part1/casper/initrd"
  local netboot="${DOWNLOAD_UBUNTU}/netboot"
  add_menu_item_netboot "${pxe_default}"  "${MENU_ITEM_UBUNTU}"
  initrd_and_kernel_to_netboot "${kernel}" "${initrd}" "${netboot}"
  docker_dhcp_tftp_reconfig_net
  change_bootloader_name_in_dhcp "pxe"
  create_mount_point_for_docker "tftp" "${netboot}"
  create_mount_point_for_docker "nfs" "${MOUNT_BASE_DIR}/part1"
}
```

Здесь примерно также, как и в **`mount_raw_rpi4`** за исключением того, что в ISO мне ничего не записать, а нужно загрузочное меню и начальная прошивка (начальный загрузчик) для сетевой карты **`pxelinux.0`** в корне TFTP сервера, этот загрузчик берется из отдельного архива netboot.tar.gz, в нем уже все есть для показа загрузочного меню.

Добавляю пункт меню в штатный Убунтовский Netboot, делаю его самым последним:


```lua
...
label ubuntu
menu label ^ubuntu-24.04.2-desktop-amd64
kernel ubuntu-24.04.2-desktop-amd64/vmlinuz
append initrd=ubuntu-24.04.2-desktop-amd64/initrd root=/dev/nfs netboot=nfs nfsroot=10.0.7.1:/nfs ip=dhcp nomodeset
```

Здесь главное выбрать правильное ядро и initrd, которые из того же дистрибутива что и корневая файловая система, которую вы грузите по NFS. Также надо учитывать что на начальном этапе загрузки PXE о NFS ничего не знает и не умеет, так что ядро и initrd обязательно должны быть на tftp сервере.

Если выбрать новый пункт меню, то начнется загрузка `ubuntu-24.04.2-desktop-amd64`, он не по умолчанию, так что нужно успеть это сделать в течении 5 сек.

Для того, чтобы не было предупреждения с графическим режимом (у меня 4k монитор и логи загрузки ядра очень маленькие), я добавил отдельно параметр nomodeset, так я выключил жутко надоедливое окно:

```
Oh no! Something has gone wrong
A problem has occured and the system can't recover
Please log out and try again
```

И наконец появиться волшебное окно  "What do you want ..."
можно выбрать:

```
   Install Ubuntu
   Try Ubuntu
```

выбрав Try Ubuntu, можно нажать появившуюся кнопку Close и окунуться в мир памяти т.е. есть в полноценный загрузочный live образ для того, чтобы протестировать оборудование, как говориться не отходя от железа, ну о пункте Install Ubuntu я наверно ничего рассказывать не буду, вы и так все знаете.

Единственное что проверил, так это подключение интернета в Ubuntu через Wifi подключение т.е. по сетевому интерфейсу мы получаем rootfs файловую систему (NFS), а вот интернет пока можно через Wifi. В Ubuntu при этом правильная маршрутизация сама подключается. Ведь шлюзом по умолчанию во время загрузке по NFS становиться наш хост (10.0.7.1), а при подключении через WiFi интернета, нужно этот маршрут перебить. Ubuntu сама справилась, а вот Raspbian уже нет.

Еще при установке "ubuntu-24.04.2-desktop-amd64.iso" на жесткий диск, установка прервалась из за неправильной контрольной суммы hash пакетов, которые приехали по NFS c хоста. Диск ISO больше 5Гб, и возможно еще с контрольными суммами, где то мне нужно разобраться. Поэтому быстренько добавил загрузку 22.04, с ним у меня проблем не было, имейте и это ввиду.

```lua
    IMAGE_NAME="ubuntu-22.04.1-desktop-amd64.iso"
    #IMAGE_NAME="ubuntu-24.04.2-desktop-amd64.iso"
```


## Самая красивая кнопка для друзей Элвиса

Вы спросите почему Элвис:

Во первых почти в каждой фирме есть RockStar(s), этакие архетипы на которых все держится, они поймут.

Во вторых я искал самую дорогую для себя плату. Дома не нашел, у меня только банановая республика какая то, платы дешевые и это не солидно. А вот на работе, такая плата нашлась и прямо на рабочем столе, она стоит как два моих домашних компьютера, она подходит. Ее и буду грузить.

Задача победить U-Boot одной кнопкой. Плата от "Элвис", на процессоре "Skif". На самом деле платы две отладочная и процессорная, но они работают в связке, так что примем их за одно устройство, будем расстраивать U-Boot.

И кстати, в руководстве на плату не нашел описания возможности сетевой загрузки, решил это как нибудь исправить. Вот код функции для запуска докера, который отвечает за загрузку по сети:

```lua
start_elvees_skif_24_06() {
  local files=(
      "Image"
      "rootfs.tar.gz"
      "elvees/mcom03-elvmc03smarc-r1.0-elvsmarccb-r3.2.1.dtb"
  )
  IMAGE_DTB="${files[2]}"
  IMAGE_NAME_SHORT="empty"
  IMAGE_DIR="${BUILD_DIR}/buildroot/output/images"
  local dtb="${IMAGE_DIR}/${IMAGE_DTB}"
  local kernel="${IMAGE_DIR}/${files[0]}"
  local rootfs="${IMAGE_DIR}/${files[1]}"
  local nfs_dir="${DOCKER_DIR_MOUNT}/nfs"
  clean_tmp_mount_dir "${nfs_dir}"

  if [[ -f "${dtb}" && -f "${kernel}" && -f "${rootfs}"  ]]; then
      echo "The version build from source code is loaded: ${IMAGE_DIR}"
      extract_tar_archive "${rootfs}" "${nfs_dir}" "sudo" || return 1
  else
      IMAGE_DIR="${DOWNLOAD_SKIF}/2024.06"
      echo "The version will be downloaded: ${IMAGE_DIR}"
      IMAGE_SKIF_URL="https://dist.elvees.com/mcom03/buildroot/2024.06/linux510/images"
      download_files "${IMAGE_DIR}" "${IMAGE_SKIF_URL}" "${files[@]}" || return 2
      extract_tar_archive "${IMAGE_DIR}/${files[1]}" "${nfs_dir}" "sudo" || return 3
  fi

  mkdir -p "${IMAGE_DIR}/pxelinux.cfg"
  local pxe_default="${IMAGE_DIR}/pxelinux.cfg/default"
  touch "${pxe_default}.orig"
  add_menu_item_netboot "${pxe_default}" "${MENU_ITEM_SKIF}"
  docker_dhcp_tftp_reconfig_net
  create_mount_point_for_docker "tftp" "${IMAGE_DIR}"

  stop_docker "dhcp_tftp_nfs:buster-slim"
  DOCKER_DIR='docker/dhcp_tftp_nfs'
  start_session_docker
}
```

Здесь предусмотрены два режима загрузки:

Первый, когда прошивка собрана из исходного кода с помощью Buildroot, это режим для разработчиков, собрали прошивку, запустили докер, инициировали режим сетевой загрузки на плате (об этом ниже), загрузили плату, что то проверили.

Всегда загружается самая последняя сборка и если она правильная, то подключаемся к плате по ssh прямо здесь же на хосте, и записываем `rootfs.tar.gz` архив по сети на EMMC диск по инструкции "Элвис", т.е. все как положено.

Второй режим "только посмотреть", это когда вы хотите все здесь и сейчас и у вас нет 4 или 5 часов на сборку. В этом случае загружаем предкомпиленный образ для платы с их сайта.

Всего то нам понадобиться только три файла и это здорово, наконец то никаких внешних загрузчиков.

Вот они эти файлы: ядро, dtb и корневая файловая система, причем сразу в архиве.

```lua
local files=(
    "Image"
    "rootfs.tar.gz"
    "elvees/mcom03-elvmc03smarc-r1.0-elvsmarccb-r3.2.1.dtb"
)
```

Далее все просто, отдаем ядро серверу TFTP через каталог где это все или собирается или загружается, и распаковываем корневую файловую систему по пути `/tmp/docker/nfs`, под рутом. Обязательно нужно сохранить права на файлы от имени root, иначе systemd в составе загружаемой rootfs по NFS работать не будет, да и еще много чего отвалиться, права процессов надо соблюдать, иначе никак.

При распаковке архива будет запрошен пароль администратора. Для U-Boot нужно создать один конфигурационный файл со стандартным именем "pxelinux.cfg/default" в корневом каталоге TFTP сервера.

Вот такой:

```dart
default linux
prompt 0
timeout 50
label linux
menu label Download Linux
kernel Image
devicetree IMAGE_DTB
append root=/dev/nfs nfsroot=NFS_IP_ADDRESS:/nfs,vers=3 rw earlycon console=ttyS0,115200 console=tty1 ip=dhcp
```

Здесь после копирования этого шаблона, будет произведена замена строк:

"IMAGE_DTB" на =>
elvees/mcom03-elvmc03smarc-r1.0-elvsmarccb-r3.2.1.dtb

и строки "NFS_IP_ADDRESS" => на 10.0.7.1 (переменная "IP_TFTP" в func.sh)

На самой плате Skif от Элвиса, нужно дернуть U-Boot и попросить его **«загрузиться по сети»**, для этого у нас есть технологический кабель USB-typeC, нужно им соединить ваш хост компьютер и плату.

И запустить загрузку с помощью следующей функции:

```bash
start_elvees_skif_netboot() {
    expect_script=$(mktemp)
    cat << 'EOF' > "$expect_script"
#!/usr/bin/expect -f
set timeout -1
set server_ip [lindex $argv 0];
spawn picocom --baud 115200 /dev/ttyUSB0

expect {
    "Hit any key to stop autoboot" {
        send " \r"
        exp_continue
    }
    "=>" {
        send "setenv serverip $server_ip\r"
        send "run bootcmd_pxe\r"
        exp_continue
    }
    "login:" {
        sleep 0.5
        interact
        exit 0
    }
    eof
    timeout
}
EOF
    chmod +x "$expect_script"
    "$expect_script" "${IP_TFTP}"
    rm -f "$expect_script"
}
```

Эта функция только прикидывается что она bash, на самом деле это не так, это гибрид, инкапсуляция одного языка в другой с помощью EOF(а) - маркера начала и конца файла.
На самом деле, это просто секция с текстовым содержимом, которая сохраняется во временном файле с уникальным именем в каталоге /tmp, bash этот файл запускает и передает ему одну переменную среды с IP адресом NFS сервера (у меня один сервер для TFTP и NFS).

Обожаю expect, он всегда находится в ожидании текстовых сообщений от любого процесса, на который вы его натравили.

Здесь этим процессом является запуск терминальной сессии через последовательный порт (UART), а на другом конце и будет наш U-Boot, запуск которого мы приостановим, передадим ему ip адрес, по которому он сможет обращаться к TFTP серверу и далее запустим сетевой режим загрузки.

Первым делом после этого U-Boot будет запрашивать загрузочную конфигурацию и в конце концов найдет ее по стандартному пути по умолчанию "pxelinux.cfg/default", ну а дальше U-Boot грузит ядро, указанное в конфигурации, грузит DTB для платы, параметры загрузки ядра у него также уже есть. После этого он передает управление ядру и его миссия на этом завершается.

Если все прошло нормально и ядро смогло подключить сетевую файловую систему NFS, то запуститься пользовательская сессия, которую мы определим по наличию сообщения "login:" и тогда expect снова вступает в игру последний раз для того чтобы переключиться в интерактивный режим.

И на этом все, можно вводить логин и пароль пользователя и работать.

Для сборки прошивки для платы Skif из исходного кода, можно воспользоваться функцией:

```lua
DOWNLOAD_DIR="$HOME/distrib"
DOWNLOAD_SKIF="${DOWNLOAD_DIR}/skif"
BUILD_DIR="${DOWNLOAD_SKIF}/mcom03-defconfig-src"

build_elvees_skif_24_06() {
  local download="${DOWNLOAD_SKIF}"
  local base_url="https://dist.elvees.com/mcom03/buildroot/2024.06/linux510"
  local file="mcom03-defconfig-src.tar.gz"
  if [ ! -d "${BUILD_DIR}" ]; then
      download_files "${download}" "${base_url}" "${file}" || return 1
      extract_tar_archive "${download}/${file}" "${download}" || return 2
  fi
  [[ -d "${BUILD_DIR}" ]] || { echo "Build dir ${BUILD_DIR} => not found for Skif board, exiting ..."; return 1; }
  cd "${BUILD_DIR}"
  export DOCKERFILE=Dockerfile.centos8stream; export ENABLE_NETWORK=1;
  ./docker-build.sh make mcom03_defconfig
  ./docker-build.sh make
  cd ${CURDIR}
}
```

Здесь сборка дистрибутива buildroot осуществляется в докере от "Элвиса", требуется где то 4 или 5 часов, это зависит от производительности компьютера.

И наконец самая красивая кнопка у меня выглядит так:
(конечно она не настолько красивая, как золотая, но тоже ничего)

```json
"actionButtons": {
    "reloadButton": null,
    "loadNpmCommands": false,
    "commands": [
        {
            "name": "StartElveesSkif-24.06",
            "singleInstance": true,
            "color": "#00008b",
            "command": "cd .vscode/yo; source func.sh; start_elvees_skif_24_06",
        },
        {
            "name": "Elvees🖲Netboot",
            "singleInstance": true,
            "color": "#000000",
            "command": "cd .vscode/yo; source func.sh; start_elvees_skif_netboot",
        }
    ]
}
```

Вместо текста на кнопки можно повесить UTF-8 красивые символы, их не так много, но поискать можно и еще есть кнопка для разработчиков:

```json
{
    "name": "Build🖲Elvees",
    "singleInstance": true,
    "color": "#007fff",
    "command": "cd .vscode/yo; source func.sh; build_elvees_skif_24_06",
},
```

Общий алгоритм работы следующий:

- подключается технологический кабель USB-typeC;
- подключается сетевой кабель от хоста к одному из портов платы;
- запускается докер (кнопка StartElveesSkif-24.06);
- запускается сессия для U-Boot (кнопка Elvees🖲Netboot);
- подается питание на плату.

## Встраиваем кнопки в VSCode паровозиком

Кнопки я буду добавлять в плагин **«seunlanlege.action-buttons»** методом паровозика, так чтобы на всех хватило. Это когда последняя кнопка первого меню, переключает его на следующее меню, а самая последняя кнопка "MenuN" переключает на первое меню, это один из вариантов (круговой), покажу на примере:

```json
"actionButtons": {
  "reloadButton": null,
  "loadNpmCommands": false,
  "commands": [
    ...
    {
      "name": "⮕ Menu2",
      "singleInstance": true,
      "color": "#000000",
      "command": "cp -f .vscode/settings.json.Menu2 .vscode/settings.json; exit",
    }
  ]
}
```

А для последнего "MenuN":

```json
...
{
  "name": "⮕ Menu1",
  "singleInstance": true,
  "color": "#000000",
  "command": "cp -f .vscode/settings.json.Menu1 .vscode/settings.json; exit",
}
```

Очень расстроился когда не нашел такую же, но только левую (это катастрофа).

```dart
символ ⮕ (U+2B95) — "Rightwards Arrow With Equilateral Arrowhead"
```

Мне круговой метод не понравился и я остановился на классическом варианте, когда видно в каком ряду кнопок мы находимся, это так:

```dart
    #          BUILD   ▶Load
    # Build◀   LOAD    ▶Install
    # Build◀   INSTALL
```

Всего у меня будет три уровня меню, это файлы:

* settings.json.build
* settings.json.load
* settings.json.install

Кнопка с заглавными буквами всегда показывает текущий уровень и еще на нее можно повесить правильное событие, для `BUILD`, это выглядит так:

```json
{
  "name": "BUILD",
  "singleInstance": true,
  "color": "#000000",
  "command": "cd .vscode/yo; source func.sh; DOCKER_DIR='docker/ubuntu_22_04'; start_session_docker",
}
```

Ну как то так, чем это удобно?
Tем что вы можете повесить на кнопки все ваши фирменные инсталляторы и они будут всегда под рукой, можно сделать классификатор какой нибудь по группам, группам групп, все как вы любите.

Для установки проекта "vscode-yocto-helper" можно попробовать выполнить команду:

```bash
curl -fsSL https://raw.githubusercontent.com/berserktv/vscode-yocto-helper/refs/heads/master/install.sh | sh
```

или так посмотреть:
```bash
    mkdir vscode-yocto-helper
    cd vscode-yocto-helper
    git clone https://github.com/berserktv/vscode-yocto-helper.git .vscode
    code .
```

Примечание: на чистой системе установку пока не проверял.

Итак, на мой взгляд, то, что получилось, — это «Сетевые загрузки», NFS я до этого не использовал, не знал, что она настолько крутая. Единственное что рекомендую не выставлять докер в интернет в режиме хоста, это небезопасно.

Статья также написана для Маргариты, в качестве примера использования возможности bash для практического применения, когда у вас есть всего несколько Makefile файлов, нет ни одного С или С++ файла, только голый bash на Docker(е) и вы хотите сделать что то хорошее.


## Постскриптум:

Пол года бегал за всеми разработчиками своего отдела, ну прямо за всеми - за всеми двумя. Кнопку предлагал (еще виртуальную), не берут, говорят загрузка у них, не до кнопки сейчас, ну тогда она ваша. А я, а что я, а я все также сижу в полной консоли, ebash(u) на bash(e), мечтаю о **«LUA»** и собираю спецтехники.
