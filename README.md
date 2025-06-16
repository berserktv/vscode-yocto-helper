# Polishing VSCode into an Indecently Good Yocto IDE: The Story of a Single Button

![](https://habrastorage.org/webt/0m/6i/xw/0m6ixw8xy0_7wdkr1xw1smlfui0.png)

"Machine translation — oops!"  ([original](https://habr.com/ru/articles/899796/))

## The Idea Behind This Project

The idea for this project suddenly struck me in early 2025. On January 2nd, I woke up with a pounding headache and an unexpected realization: I needed to create something good—something good for you, as my daughter Margarita says, «for those on the Internet.» At the very least, I needed a Raspberry Pi 4 computer lab, or maybe even a Docker farm.

I adore Visual Studio Code, but I’ve never had enough time to fully explore its vast functionality—its configurations, tasks, and JSON-defined launch setups. So I decided to bypass that. What I’ve always missed are a few menu items performing highly specific functions I need while building Yocto Project distributions for embedded firmware.

It all started with the need to have my custom menu always within reach. The best spot? VSCode’s Status Bar—nothing comes closer. I began searching for a plugin offering this capability. This article is part of the DockerFace series.

**Table of Contents:**

- Selecting and configuring a VSCode plugin
- Flashing a Yocto image to an SD card
- Building Yocto images in Docker
- Using the "Baron Munchausen Method" for Bash documentation
- Running Yocto RPi images in QEMU virtual machines
- Deploying the DemoMinimal image from Yocto’s reference setup
- Dishing Out Buster Slim for an Ultimate Docker Breakdown
- Configuring DHCP, TFTP, and NFS servers
- Network-booting a core-image-minimal (wic) image on RPi4
- Network-booting Raspbian for Raspberry Pi 4
- Bonus: Network-booting Ubuntu ISO images
- Automated Yocto log analysis with DeepSeek
- "The most beautiful button for Elvis’ friends"
- Embedding buttons like a train in VSCode’s Status Bar


## VSCode Plugin Selection

The plugin is called "VsCode Action Buttons" (seunlanlege.action-buttons). It does exactly what I needed – it allows you to attach/execute any bash code with a button click.

First of all, you need to install both VSCode itself (if you don't have it installed yet) and the plugin itself:


```bash
sudo apt install -y snap
sudo snap install --classic code
code --install-extension seunlanlege.action-buttons
```

Plugin settings are added to `.vscode/settings.json` and the shell script call looks like this:

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
            "command": ".vscode/script1.sh"
        },
        {
            "name": "Button-N",
            "singleInstance": true,
            "color": "#ff007f",
            "command": ".vscode/scriptN.sh"
        }
    ]
}
```

Note: In this example it's bash code, but the executable can be in any language — you could even run a plain binary executable, whatever suits one's needs.


## Writing a Yocto Image to an SD Card

First in Yocto, I needed to flash the build output to a microSD card using a card reader. This SD card is then inserted into a single-board computer like a Raspberry Pi 4, and the board boots from it.

All required functionality resides in a shared file `.vscode/yo/func.sh`
and I'll be executing functions from there.

So initially, I need to find the list of possible image files for SD card flashing. The target platform name `YO_M` is sourced from the main configuration file "build/conf/local.conf", while the file extension for dd-command flashing is stored in the `YO_EXT` variable.

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

The result of the `find_name_image()` function will be stored in the string variable `YO_IMAGE_NAME`, with the names of found images separated by spaces.

Next, I need to locate the SD card connected via USB or card reader. A highly convenient table-formatted output is generated, allowing me to verify that exactly the correct device is selected. This is critical because after flashing with the dd command, all existing data is erased - making accuracy essential here.

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

All found storage devices are stored in the variable `LI_DISK`, and the function `select_dd_info` presents a list of options numbered from 1 to N, representing possible combinations of the dd command for the image and disk.

To proceed with writing, select the desired option, enter the corresponding number, and press Enter. The writing process is executed with the `sudo` command, giving you an additional opportunity to double-check the correct device selection.

If the image file is contained in a bz2 archive, it will be extracted before writing.

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
              if echo "$image" | grep -q "\.wic\.bz2"; then
                  echo "bzip2 -dc $image | sudo dd of=/dev/$i bs=1M"
                  mount | grep "^/dev/$i" | awk '{print $1}' | xargs -r sudo umount
                  bzip2 -dc $image | sudo dd of=/dev/$i bs=1M; sync
              else
                  echo "sudo dd if=$image of=/dev/$i bs=1M"
                  mount | grep "^/dev/$i" | awk '{print $1}' | xargs -r sudo umount
                  sudo dd if=$image of=/dev/$i bs=1M; sync
              fi
          fi
          j=$((j+1))
      done
  done
}
```

If the selected disk has mounted partitions, they must be unmounted before writing. The `sdcard_deploy` function is used to write the distribution to the memory card.

```bash
sdcard_deploy() {
  if find_sd_card && find_name_image; then
      cd "${YO_DIR_IMAGE}/${YO_M}"
      select_dd_info
  fi
}
```

Functionality from the `.vscode/yo/func.sh` script should be split up, as you can pile up numerous functions over time that become tangled:

some working, some outdated, some unreliable. Verified functions should be migrated to separate scripts - I'll demonstrate using `.vscode/yo/sdcard_deploy.sh` as an example:

```bash
#!/bin/bash
this_f=$(readlink -f "$0")
this_d=$(dirname "$this_f")
source $this_d/func.sh
sdcard_deploy
```

This is especially useful for modularizing functionality, where a single working script performs, ideally, one and only one top-level function.

The readlink and dirname commands are used to construct absolute paths to the executable file and directory. This avoids confusion with relative paths, which often lead to errors—absolute paths minimize such issues.

Finally, after clicking the button in the VSCode status bar, select the image and disk for writing, and the distribution will be recorded (see `.vscode/settings.json`):

```json
{
    "name": "SDcardDeploy",
    "singleInstance": true,
    "color": "#007fff",
    "command": "cd .vscode/yo; ./sdcard_deploy.sh"
}
```

For the «seunlanlege.action-buttons» plugin, the current directory is where the ".vscode" configuration resides. Therefore, before calling the write function, I change the current directory—this is essentially a calling convention to standardize button command additions. For the "YO_R" variable,
I've implemented an additional check that triggers if its initial relative path is specified incorrectly:

```bash
# root yocto directory (where the build directory will be located), relative to the current directory
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

This code resides at the very beginning of the `func.sh` script. Here, the root directory is identified by the presence of the `setup-environment` file, which handles the creation of the initial build directory tree structure, such as:

```dart
 root Yocto directory
    ├── build
    ├── downloads
    ├── setup-environment
    ├── shell.sh
    └── sources
```


## Building Yocto Images in Docker

The next VSCode function I need is one that allows building Yocto distributions with different toolchains. For older Yocto branches on modern host systems like Ubuntu 24.04, everything constantly breaks—wrong GCC versions, linker issues, or needing ancient CMake versions. 

There's always complete incompatibility between the build tools and what I'm trying to compile. Honestly, without Docker, it's better not to even touch legacy builds—it's a complete nightmare. 

Frankly, I recommend always building in Docker, even for newer projects.

Docker configurations reside in the `.vscode/yo/docker` directory—for example => `ubuntu_22_04`:

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

The Dockerfile contents are as follows:

```dart
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
```

The container runs under the user account, but to handle unexpected issues, the password "docker" is added for the root user (commented in code). You can connect to the running container as root to install packages using apt.

After resolving dependency problems, add the names of these missing packages directly to the Dockerfile. Once the container image is debugged, comment out this line.

A Makefile is used for Docker operations:

```dart
IMAGE = ubuntu_22_04
# Build directory inside the container - must match the path in Dockerfile (see WARNING label)
PUB   = "/mnt/data"
# Path to root build directory containing setup-environment file (default: ../docker if not set)
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
	
# Remove all stopped containers
clean-all-container:
	sudo docker rm $(docker ps -qa)
	
	
.PHONY: run build clean-all-container
```

Here, Docker is launched as follows:

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

Where:

* `--rm` - Automatically removes the container after it exits;
* `--network=host` - Eliminates network isolation between container and host. Directly uses host's network resources.   
  **Security warning:** Only use when the container is intended for internal, externally-closed networks;
* `-v` (or `--volume`) - Creates storage space within the container separate from its filesystem. Volumes don't increase 
  container size. Here: forwards host's SSH agent socket for SSH authorization inside the container;
* `--cap-add=cap_net_admin` - Privilege allowing mounting/unmounting filesystems;
* `--cap-add=cap_sys_admin` - Grants system administration capabilities without making the container fully privileged;
* `--cap-add=cap_net_raw` - Privilege enabling RAW/PACKET socket creation. Required for sending/receiving ICMP packets within the container;
* `--mount` - Mounts the root Yocto directory (containing `build/` with all build artifacts) into container. **Critical  benefit:** Preserves build outputs on host, allowing container termination/deletion without data loss. **Yocto limitation:** Build path hardcoded after first `setup-environment` run. Changing `PUB` mount point (/mnt/data) breaks builds - Bitbake will throw path errors;
* `-d` - Runs container in background (detached mode);
* `-t` - Allocates pseudo-TTY terminal. Container persists until terminal session ends.


The `IMAGE` variable specifies the primary name for launching the container.

Additionally, to run Docker in the foreground (instead of background), remove the "-d" option and add "-i". This starts the container in interactive mode, allowing direct command input in its running shell. The Makefile separates these modes:

- make run: Interactive mode with Yocto initialization (executes setup-environment);
- make run_detach: Background container launch. To connect to an already running 
  container for executing a single bitbake command, each start creates a shell 
  session initialized with setup-environment, followed by execution of the user command.

Next, to work with this Makefile, I need to add a function to `.vscode/yo/func.sh` that finds the ID of the running Docker container:

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

The search result is stored in the variable `CONTAINER_ID`
and used in the `start_cmd_docker()` function to execute commands inside the container:

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

Where the first argument can be a command or list of commands separated by ";" 
The key requirement is that the `DOCKER_DIR` variable contains the correct path to the Docker Makefile directory.

The `start_cmd_docker` function first searches for the container hash ID by name (visible in the Makefile, see IMAGE=ubuntu_22_04). If the container isn't running, it starts in background mode (make run_detach), then connects via docker exec to launch a new bash process. Within this process, the commands passed as the first argument `$cmd_args` are executed.

An additional check verifies the existence of the build directory - if missing, container commands won't execute.

Usage of this function is documented in the shell script `.vscode/yo/build_image.sh`:

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

The launch process is split into two parts:
static: `cmd_init` and dynamic `cmd_run` (containing commands to execute within the Yocto environment), for example:

- bitbake image_name_to_build;
- bitbake specific_recipe_to_build;
- etc.

cmd_init initializes the Yocto build environment for the specified target platform. The `setup-environment` script receives the platform name (sourced from `build/conf/local.conf`).

The `build_image.sh` script launch - triggered by a status bar button - is configured in `.vscode/settings.json` as follows:

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
      "command": "cd .vscode/yo; source func.sh; DOCKER_DIR='docker/ubuntu_22_04' start_session_docker"
    },
    {
      "name": "BuildImage",
      "singleInstance": true,
      "color": "#007fff",
      "command": "cd .vscode/yo; ./build_image.sh 'bitbake core-image-minimal'"
    }
  ]
}
```

Additionally, pressing the Build button launches an interactive bitbake session, handled by the `start_session_docker()` function defined in `.vscode/yo/func.sh`:

```bash
  start_session_docker() {
      cd "${DOCKER_DIR}"
      make build && make run
      cd "${CURDIR}"
  }
```

Here, the actual launch of the shell process is described in the final line:

Dockerfile: ENTRYPOINT ["./shell.sh"]

In this scenario, a terminal remains running in VSCode that you can always access to work with your Yocto build.

## Running Yocto Builds for Raspberry Pi on QEMU Virtual Machine

The next function I wanted to add to VSCode enables running and debugging Yocto distributions without a physical Raspberry Pi board. When the board is unavailable, this allows testing newly built Yocto images. I'll demonstrate using Raspberry Pi 3 as an example—note only 64-bit images can be launched this way.

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

Where:

`qemu-system-aarch64` - launches QEMU for 64-bit builds. If you attempt to run a distribution built for 32-bit architecture, you may encounter a completely blank terminal—no kernel output whatsoever. In such cases, the following option proves invaluable:

`-d in_asm -D QEMU_log.txt` - logs all assembly instructions to a separate file. This slows execution significantly, but if you've mixed up processor architectures, you absolutely need this diagnostic output.

**Parameters:**  

* `-m 1G`: RAM allocation (1 gigabyte)
* `-M raspi3b`: Machine type (Raspberry Pi 3 Model B)
* `-dtb bcm2837-rpi-3-b.dtb`: Device Tree Blob for target board. Essential for boot - without it, the kernel cannot 
  initialize RPi3 hardware. Describes all board components: 
  CPU, peripherals, memory addresses, and device interrupts.  
* `-kernel Image`: Kernel filename to execute
* `-serial mon:stdio`: Redirects serial port output to your terminal's stdout. 
  All VM serial output appears in the 
  QEMU launch terminal, enabling bidirectional terminal communication.  
* `-drive file=${image},format=raw,if=sd,readonly=off`: Attaches virtual disk as writable SD card in raw format.
  Contains partition table with two logical drives 
  (see `fdisk -l $image`). The second drive hosts the rootfs.  
* - append "console=ttyAMA0,115200 root=/dev/mmcblk0p2 rw earlycon=pl011,0x3f201000": Console configuration:  
  - `console=ttyAMA0,115200`: Primary Linux kernel-user communication channel  
  - `root=/dev/mmcblk0p2 rw`: Mounts second partition as read-write root filesystem  
  - `earlycon=pl011,0x3f201000`: Early boot output (pre-driver initialization):  
    - `pl011`: UART controller type in Raspberry Pi  
    - `0x3f201000`: Controller's memory-mapped registers (hardware-specific to RPi)  
      Note: ttyAMA0 always maps to pl011 UART in Raspberry Pi  
* `-nographic`: Disables graphical output. VM runs in text mode with all guest OS output displayed in the launch   
  terminal. Enables monitoring/interaction via text commands only.  


For QEMU raspi3b, use a DTB with better emulation compatibility: dtb="bcm2837-rpi-3-b.dtb".

Additional debugging options are available:
"-d guest_errors,unimp,cpu_reset -D QEMU.log"

These enable various debug information categories, logged to a separate file:

* `guest_errors`: Captures errors occurring within the guest OS;
* `unimp`: Logs attempts to use unimplemented instructions or features in emulated hardware;
* `cpu_reset`: Records CPU reset-related events.

On actual Raspberry Pi 3 hardware, the GPU serves as the primary controller - it's the master component, with the CPU operating in full dependency. The proprietary bootloader bootcode.bin typically resides on the SD card's first boot partition. Its primary function is loading GPU firmware => start.elf and fixup.dat (or start4.elf depending on board version), then transferring execution control. The GPU firmware subsequently parses the configuration file [config.txt](https://www.raspberrypi.com/documentation/computers/config_txt.html)

It forms kernel boot parameters and transfers control to the CPU to launch the kernel.

The qemu-system-aarch64 ... command presented earlier operates slightly differently:

First, we completely remove the GPU from this chain - we bypass it by directly loading the kernel via the -kernel parameter. This approach is faster and less error-prone. While we retain all boot files (bootcode.bin, start.elf, etc.) on the SD card's first boot partition for compatibility, QEMU ignores them during this direct boot process:

see `-drive file=${image}` (mapped to /dev/mmcblk0p1 in-system), but I prefer not to validate secondary/tertiary bootloader mechanisms. 

Frankly, GPU emulation level for `-M raspi3b` in QEMU remains unclear. The critical requirement is passing an accurate dtb="bcm2837-rpi-3-b.dtb" to the kernel - without it, nothing functions.

Boot sequence: The kernel launches → initializes hardware → mounts root filesystem → OS transitions to target runlevel → spawns virtual terminals via getty processes. These create user I/O sessions. If we've correctly associated getty with our emulated `pl011 UART controller => /dev/ttyAMA0`, we'll see the login: prompt, enabling password entry and system access.

There's another nuance here:

If you make no changes to the image, getty won't associate with /dev/ttyAMA0. To enable this association, you must build the image with additional configuration:

```dart
  # Assumes system boots via SysVinit
  # Not tested with Systemd (different implementation there)
  SERIAL_CONSOLES = "115200;ttyAMA0"
  SERIAL_CONSOLES_CHECK = "ttyAMA0:ttyS0"

  # These parameters will modify
  # the system file /etc/inittab in the image
  # and associate getty with the serial port

  # Parameters are added to
  # the layer configuration file in local.conf
```

Note: overall, this approach proves quite inconvenient - specifically rebuilding core-image-minimal just for QEMU VM execution. However, you can dynamically modify /etc/inittab within `core-image-minimal.wic`: First mount it using `mount_raw_image()` (see below), adjust the configuration, save changes, then call `umount_raw_image()`


## Using the Baron Munchausen Method for Bash Self-Documentation

Here I'd like to present a simple example of self-documenting bash code:

```bash
#!/bin/bash

help() {
    local script_path=$(realpath "${BASH_SOURCE[0]}")
    grep -A 1 "^# " "${script_path}" | sed 's/--//g'
}

# Example bash function 1 (included in interface description)
example_bash_function1() {
    echo "example_bash_function1"
}

# Example bash function 2 (included in interface description)
example_bash_function2() {
    echo "example_bash_function2"
}

#Example bash function 3, excluded from interface description
example_bash_function3() {
    echo "example_bash_function3"
}

help
```

This approach is convenient because when working with the script via:
`source name_script.sh`
you immediately see all available script interfaces.

To include a function in this documentation, simply add a comment line immediately before the function declaration. The comment must: 

- Begin at the start of the line
- Contain a space after the # symbol

To exclude a function from documentation, omit the space after # in its preceding comment. Comments inside bash functions won't appear in the help output because they:

- Don't start at the beginning of the line
- Are indented by at least 4 spaces (assuming proper script formatting)

How it works:

* realpath: Converts relative paths to absolute paths;
* grep -A 1 "^# ": Finds lines starting with "# " and captures the next line;
* sed 's/--//g': Removes the -- characters added by grep.

Of course, there are drawbacks: For large scripts, this approach can appear cumbersome. When dealing with numerous functions, it's not always justified.

Advantages include: Function names remain consistently up-to-date forces concise single-line descriptions - if you can't explain a function in one line, reconsider its necessity.


## Deploying the YoctoDemoMinimal Image from the Yocto Box

For working with Yocto Project, I’ve prepared a practical example — a configuration for building a minimal Yocto image for the Raspberry Pi 4 board. Pressing this button executes the following code:

```bash
example_yocto_demo_minimal_rpi4() {
  local proj_demo="${YO_DIR_PROJECTS}/yocto-demo-minimal"
  mkdir -p "${proj_demo}"
  cd ${proj_demo}
  repo init -u https://github.com/berserktv/bs-manifest -m raspberry/scarthgap/yocto-demo-minimal.xml
  repo sync
  # first start (create build)
  echo "exit" | ./shell.sh
  # script for start VSCode
  echo "#!/bin/bash" > start-vscode.sh
  echo "cd sources/meta-raspberrypi" >> start-vscode.sh
  echo "code ." >> start-vscode.sh
  chmod u+x start-vscode.sh
  # start new VSCode instance
  cd sources/meta-raspberrypi
  git clone https://github.com/berserktv/vscode-yocto-helper.git .vscode
  # rm -fr .vscode/.git
  code .
}
```

Thus, the plugin button configuration is copied to the source code directory of a selected Yocto Project layer - specifically, the layer I designate as the primary development directory. In my example, this is the BSP layer for Raspberry Pi 4 support: => "meta-raspberrypi".

A second VSCode instance is then launched with this new configuration. Within this environment, the build buttons appear in their native habitat, allowing you to build the "core-image-minimal" Yocto image out-of-the-box.

## Dishing Out Buster Slim for an Ultimate Docker Breakdown

Next, I'll tackle booting the built core-image-minimal for Raspberry Pi 4. The next function I absolutely need is network booting for Raspberry Pi 4. This requires only an Ethernet cable - incredibly convenient. You can build a distribution version, load it over the network, test something, reload it, and repeat.

The setup assumes one host interface (e.g., Wi-Fi) provides internet access, while the second network interface remains free. We'll directly connect this free interface via cable to the Raspberry Pi 4's network port.

Without modifying the Yocto configuration or meta-raspberrypi layer, the build produces an archived wic image: `bz2 => core-image-minimal-raspberrypi4-64.rootfs.wic.bz2`

If you unpack it, you can examine its structure using the command:

`fdisk -l core-image-minimal-raspberrypi4-64.rootfs.wic`

This is a standard RAW image containing a partition table with two logical partitions:

- A FAT32 boot partition;
- An ext4-formatted rootfs partition.

To mount this image, I've implemented the following code:

```bash
mount_raw_image() {
  if [[ -z "${IMAGE_DIR}" || -z "${IMAGE_NAME}" || -z "${MOUNT_DIR}" ]]; then
      echo "Error: Set environment variables IMAGE_DIR, IMAGE_NAME, and MOUNT_DIR" >&2
      return 1
  fi

  local image_file="${IMAGE_DIR}/${IMAGE_NAME}"
  if [ ! -f "${image_file}" ]; then
    echo "Error: Image file ${image_file} not found" >&2
    return 2
  fi

  local loop_dev=$(losetup -j "${image_file}" | awk -F: '{print $1}')
  if [ -z "${loop_dev}" ]; then
    echo "sudo losetup -f --show -P ${image_file}"
    loop_dev=$(sudo losetup -f --show -P "${image_file}")
    if [[ $? -ne 0 ]]; then echo "Error: Failed to create loop device" >&2; return 3; fi
    echo "Created new loop device: ${loop_dev}"
  else
    echo "Using existing loop device: ${loop_dev}"
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
        echo "Partition ${part_num} is already mounted at ${mount_point}, skipping..."
        continue
      fi

      mkdir -p "${mount_point}"
      echo "sudo blkid -o value -s TYPE ${partition}"
      local fs_type=$(sudo blkid -o value -s TYPE "${partition}")
      case "${fs_type}" in
        vfat)
            sudo mount -o rw,uid=${uid},gid=${gid} "${partition}" "${mount_point}" ;;
        *)
            sudo mount -o rw "${partition}" "${mount_point}" ;;
      esac

      if [[ $? -eq 0 ]]; then echo "Partition ${part_num} mounted at ${mount_point}";
      else echo "Error mounting partition ${part_num}" >&2; fi
    fi
  done
}
```

Here, I leverage a kernel mechanism that enables treating regular files as block devices. Loop devices essentially "wrap" files into virtual disks, allowing the system to interact with them identically to physical hardware.

The primary Linux utility for this is losetup. Different filesystem types may require slightly different parameters. For example, with FAT32, you can't edit files as a regular user without UID/GID mapping - and I absolutely need this capability.

The function requires three environment variables as parameters:

**`IMAGE_NAME`** - image filename
**`IMAGE_DIR`**  - directory containing the image file
**`MOUNT_DIR`**  - mount target directory

Note: This implementation additionally utilizes the `get_mount_base()` function:

```lua
MOUNT_BASE_DIR=""
IMAGE_NAME_SHORT=""
get_mount_base() {
    local name_without_ext="${IMAGE_NAME%.*}"
    MOUNT_BASE_DIR="${MOUNT_DIR}/${name_without_ext}"
    IMAGE_NAME_SHORT="${name_without_ext}"
}
```

This function uses the image name `IMAGE_NAME` to determine the base mount point within the `MOUNT_DIR` directory. Since the image is composite and may contain N partitions, each partition is mounted under standardized names (part1, part2, etc.). This establishes consistent naming conventions for any raw image.

Additionally, it sets a variable for the shortened image name.

For example:
From: core-image-minimal-raspberrypi4-64.rootfs.wic
To: core-image-minimal-raspberrypi4-64.rootfs

For unmounting, I use `umount_raw_image()` with the same environment variables:

```lua
umount_raw_image() {
  if [[ -z "${IMAGE_DIR}" || -z "${IMAGE_NAME}" || -z "${MOUNT_DIR}" ]]; then
    echo "Error: Set environment variables IMAGE_DIR, IMAGE_NAME, and MOUNT_DIR" >&2; return 1
  fi

  get_mount_base
  local name_without_ext="${IMAGE_NAME%.*}"
  if [ ! -d ${MOUNT_BASE_DIR} ]; then
    echo "Error: ${MOUNT_BASE_DIR} not found, exiting ..." >&2; return 2
  fi

  local mounted_parts=("${MOUNT_BASE_DIR}"/part*)
  if [[ -e "${mounted_parts[0]}" ]]; then
    for mount_point in "${mounted_parts[@]}"; do
      if mountpoint -q "${mount_point}"; then
        echo "sudo umount ${mount_point}"
        sudo umount "${mount_point}"
        if [[ $? -eq 0 ]]; then echo "Successfully unmounted ${mount_point}"
        else echo "Error: Failed to unmount ${mount_point}" >&2; fi
      else
        echo "Warning: ${mount_point} is not mounted" >&2
      fi
    done
  else
      echo "No mounted partitions found in ${MOUNT_DIR}/${name_without_ext}"
  fi

  local image_file="${IMAGE_DIR}/${IMAGE_NAME}"
  if [[ -f "${image_file}" ]]; then
    local loop_devices
    loop_devices=$(losetup -j "${image_file}" | awk -F: '{print $1}')
    for loop_dev in ${loop_devices}; do
      echo "sudo losetup -d ${loop_dev}"
      sudo losetup -d "${loop_dev}"
      if [[ $? -eq 0 ]]; then echo "Successfully detached loop device ${loop_dev}"
      else echo "Error: Failed to detach loop device ${loop_dev}" >&2; fi
    done
  else
    echo "Warning: Image file ${image_file} not found, skipping loop device cleanup" >&2
  fi
}
```

With the `mount_raw_image()` and `umount_raw_image()` functions implemented, I can now proceed with network boot setup. 

For this purpose, I'll utilize the Buster Slim Docker container: "debian:buster-slim".


## Configuring DHCP, TFTP, and NFS servers

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

Main Dockerfile:

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

This installation configures three core servers essential for network booting: DHCP, TFTP, and NFS.

The launch script `entrypoint.sh` appears as follows:

```bash
#!/bin/sh

# Make sure we react to these signals by running stop() when we see them - for clean shutdown
# And then exiting
trap "stop; exit 0;" TERM INT

stop()
{
# We're here because we've seen SIGTERM, likely via a Docker stop command or similar
# Let's shutdown cleanly
    echo "SIGTERM caught, terminating process(es)..."
    echo "NFS Terminate..."
    exportfs -uav
    service nfs-kernel-server stop
    echo "TFTP Terminate..."
    service tftpd-hpa stop
    echo "DHCP Terminate..."
    service isc-dhcp-server stop

    exit 0
}

start()
{
    echo "Starting services..."
    echo "DHCP init..."
    service isc-dhcp-server start
    echo "TFTP init..."
    service tftpd-hpa start
    echo "NFS init..."
    service rpcbind start
    service nfs-common start
    service nfs-kernel-server start
    exportfs -rva

    echo "Started..."
    while true; do sleep 1; done

    exit 0
}

start
```

To launch the Buster Slim container, a Makefile is used:

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
    sudo nmcli connection delete "static-host-net" >/dev/null 2>&1 || true
    sudo nmcli connection add type ethernet con-name "static-host-net" \
        ifname ${HOST_NET_IFACE} ipv4.address ${IP_ADDR}/${IP_MASK2} \
        ipv4.method manual connection.autoconnect yes
    sudo nmcli connection up "static-host-net"

    sudo modprobe nfsd
    @sudo systemctl stop rpcbind.socket rpcbind > /dev/null 2>&1 || true

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

Here, Docker runs in privileged mode and mounts several core configuration files for DHCP and NFS during startup.

For the most basic setup, you can configure the following network interface files within Docker:

```lua
########################################
# configuration /etc/network/interfaces
######################################
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet static
address 10.0.7.1
netmask 255.255.255.0
```

Since the Buster Slim container runs in host network mode (--network=host), the network interface name must match the host's interface - in this example, "eth0".

DHCP server configuration within Docker:

```lua
#############################################
# configuration /etc/default/isc-dhcp-server
###########################################
DHCPDv4_CONF=/etc/dhcp/dhcpd.conf
DHCPDv4_PID=/var/run/dhcpd.pid
INTERFACESv4="eth0"

#####################################
# configuration /etc/dhcp/dhcpd.conf
###################################
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

For DHCP configuration, you must first specify the listening network interface - which must match the host's interface name. Next, define: the dynamic address pool range, gateway address, subnet mask, TFTP server address (which distributes files), and crucially, the primary network bootloader "bootcode.bin" (though I have questions about whether it's truly primary or secondary - but that's not the core issue here).

The critical point is: when network-booting a Raspberry Pi 4, this bootloader must reside in the TFTP server's root directory. Otherwise, the boot process fails completely.

By default, Raspberry Pi 4 prioritizes booting from microSD cards first, followed by USB devices, with network boot as the last option.

You can easily verify this: Connect an HDMI monitor, remove the SD card, and power on the board. With no SD card or USB drive connected, network boot should initiate - visible through the beautiful splash screen displaying a «network boot» startup message.

If issues persist, you may need to update the EEPROM variable controlling Raspberry Pi 4's boot order:

```lua
################################
# On Desktop computer
################################
# Install Raspberry Pi Imager
sudo apt install rpi-imager

# Insert microSD card into card reader for EEPROM update
# Launch rpi-imager program
rpi-imager

# Select OS to install (CHOOSE OS)
=> Misc utility images (Bootloader EEPROM configuration)
=> Bootloader (Pi 4 family)

# Choose one of three images with different boot priorities
# Recommend selecting boot priority: SD => USB => network
# i.e., network boot has lowest priority

# Wait for write completion. If successful,
# connect SD card to Raspberry Pi 4
# If you connect debug USB-UART to GPIO, you can monitor update process
sudo picocom --baud 115200 /dev/ttyUSB0

# After powering the board, UART at least shows progress, e.g.:
...
Reading EEPROM: 524288
Writing EEPROM
......................................................................................+....+
Verify BOOT EEPROM
Reading EEPROM: 524288
BOOT-EEPROM: UPDATED

# If no UART(A), monitor LEDs - they provide status clues
```

NFS server configuration in Docker:

```lua
###############################################
# configuration /etc/default/nfs-kernel-server
#############################################
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

############################
# configuration /etc/export
##########################
/nfs  *(rw,fsid=0,sync,no_subtree_check,no_root_squash,no_all_squash,crossmnt)
```

Here I enable version 4 where possible, though other versions should also work.

NFS export configuration:

* `rw` - read and write permission;
* `fsid=0` - specifies this as the root export for NFSv4. In NFSv4, clients mount a "virtual"
  root filesystem (e.g., /), with all other exports becoming its subdirectories;
* `sync` - requires synchronous disk writes before acknowledging operations,
  guaranteeing data integrity at the cost of performance;
* `no_subtree_check` - disables verification that files are within the exported directory on each access request;
* `no_root_squash` - preserves root user permissions from the client (no mapping to anonymous user).
  Grants clients full root access to server files. Essential for bootable OS rootfs since
  the launched OS wouldn't function properly otherwise;
* `no_all_squash` - preserves original UID/GID of client users on the server (no anonymous mapping).
  Also essential - see previous point.

I'd also like to note that specifically with the NFS server, I encountered several issues:

- First, it can only operate exclusively - meaning if you run two such Docker containers, the second
  will interfere with the first. I solve this by running the container
  without background mode (removing `make run_detach`),
  and always stopping all found containers with this name before launching;
- Second, in `network=host` mode, Docker will use the host's kernel module, requiring `modprobe nfsd`
  before starting the container;
- Third, before launching the container, you need to disable the `rpcbind` service on the host 
  as it also interferes with Docker.
  So if your desktop computer can't do without `rpcbind`, you might need to postpone the boot process,
  keep this in mind.

```cmake
sudo modprobe nfsd
@sudo systemctl stop rpcbind.socket rpcbind > /dev/null 2>&1 || true
```

Let's revisit the Buster Slim Makefile once more:

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

The `HOST_NET_IFACE` variable specifies the name of the host network interface that matches what's defined in `/etc/network/interfaces` and `/etc/default/isc-dhcp-server`.

When working with Docker, I first execute the shell script `docker/dhcp_tftp_nfs/reconfig_net.sh` to automatically configure `/etc/network/interfaces`, `/etc/default/isc-dhcp-server`, and several other files.

This reconfiguration occurs only when the Makefile variable `HOST_NET_IFACE=""` is empty.

After reconfiguration, the script updates this variable with the identified local network interface name (e.g., `HOST_NET_IFACE="eth0"`), meaning the setup effectively runs just once.

The `reconfig_net.sh` script uses these variables from the `Makefile` for configuration:  
`IP_ADDR` `IP_SUBNET` `IP_MASK` `IP_RANGE`  
allowing you to add custom local configurations. However, there's one challenge: I identify the host computer's local network interface as follows:

```lua
ip link show | awk -F: '$0 !~ "lo|vir|docker|veth|br|wl" {print $2; getline; print $2}' | tr -d ' ' | head -n 1

# and if you happen to have two local network interfaces,
# this might not work
# requiring you to manually configure
# the aforementioned files

# there's also an issue
# with the IP_TFTP="10.0.7.1" variable in func.sh
# currently it is static
# meaning if you change IP_ADDR in the Makefile
# you must also update this variable
```

The Makefile also specifies core base directories `TFTP_DIR` and `NFS_DIR`, which are always mounted into Docker at startup. These could be symbolic links to directories representing mount points obtained through the `mount_raw_image()` function.

For `core-image-minimal-raspberrypi4-64.rootfs.wic` for example:  
link `/tmp/docker/tftp` => `core-image-minimal-raspberrypi4-64.rootfs/part1`  
link `/tmp/docker/nfs`  => `core-image-minimal-raspberrypi4-64.rootfs/part2`

We serve the boot partition via TFTP, while the root rootfs partition is served by the NFS server.

What does this resemble? Buster Slim hasn't failed us - we're about to witness "The Grand Image Dissection".


## Image Dissection

So what's great about image dissection? It makes you completely indifferent to what you load - whether it's "Raspbian", "Bubuntu", or "mcom03" (exclusively for Elvis' friends). Later, we'll load something from this list by adding a few dozen lines of bash code and tweaking Docker.

In this scenario, the Buster Slim Docker **works wonders**. This is an awesome breakdown.

What's equally fascinating is that it doesn't matter what you load - but also where you load it. Throw away the Raspberry Pi 4, connect via Ethernet to a neighboring computer (if it supports PXE network boot), select network boot in BIOS, add another bash code section, and boot that computer.

Mission: Load all assets within visual range.

In some cases, when an image is loaded, it will think it's running natively. For Raspbian, the image is physically a single file containing a partition table and logical drives. After mounting via `losetup`, the image gets dissected into multiple logical drives (usually two), and each mount point will behave according to its filesystem capabilities - ext4 allows writing, ISO is read-only, etc.

Free space in the image is usually limited since minimizing image size is crucial, but this can be fixed for long-term use of the same image. After all, a good image should always be at hand.


## Loading core-image-minimal (wic) image onto Raspberry Pi 4 over the network

So the top-level code that initiates network boot:

```lua
start_netboot_rpi4() {
    DOCKER_DIR='docker/dhcp_tftp_nfs'
    stop_docker "dhcp_tftp_nfs:buster-slim"
    mount_raw_rpi4 && start_session_docker
}
```

Next, the `mount_raw_rpi4()` function:

```lua
mount_raw_rpi4() {
    if ! set_env_raw_rpi4; then return 1; fi

    mount_raw_image
    docker_dhcp_tftp_reconfig_net
    change_bootloader_name_in_dhcp "raspberry"
    raspberry_pi4_cmdline_for_nfs "${MOUNT_BASE_DIR}/part1"
    create_mount_point_for_docker "tftp" "${MOUNT_BASE_DIR}/part1"
    create_mount_point_for_docker "nfs" "${MOUNT_BASE_DIR}/part2"
    # problem with video adapter: used fake kms (old driver)
    sed -i "s|^dtoverlay=vc4-kms-v3d|#&\n dtoverlay=vc4-fkms-v3d|g" "${MOUNT_BASE_DIR}/part1/config.txt"
}
```

Here I first mount the selected image using `losetup`, and after everything is mounted:
- Change the loader name for the DHCP server => to  
  `option bootfile-name "bootcode.bin";`
- Modify the kernel parameters for network boot in the standard `cmdline.txt` file on the first,  
  bootable partition of the image => to  
  `console=serial0,115200 console=tty1 root=/dev/nfs nfsroot=10.0.7.1:/nfs,hard,nolock,vers=3 rw ip=dhcp rootwait`
- Map the correct mount points to our TFTP and NFS server;
- Fix an issue I encountered during display output by enabling an older video driver  
  (didn't investigate deeply why, but I take the `meta-raspberrypi` layer as-is without modifications)

What I'd like to note:

The list of files requested by our closed-source **bootcode.bin** appears to be hardcoded in it.  
I couldn't change the kernel filename by modifying the standard **config.txt** on the first partition:

```lua
kernel=kernel_filename
```

There's also a binding to a directory with a standard name for a specific board in the TFTP root:  
`<serial_number>/config.txt`  
but this doesn't work for me - I need to boot any board. Therefore, we could try:  
Simply supply `bootcode.bin` with the filename it expects by either:
- Creating a copy of the kernel (symlinks don't work on FAT)
- Renaming the existing kernel on the first partition to what the loader expects (if space is tight there)

For `YoctoDemoMinimal` (scarthgap branch), I didn't need to do this - the name was already correct.

To discover what `bootcode.bin` requires, you can examine the request protocol on the host:

```lua
sudo tcpdump -i eth0 -vvv -n "(port 67 or port 68) or (udp port 69)"
```

Also don't forget to change the name of your host network interface.

Let's break down the parameters:

* `console=serial0,115200 console=tty1`: enables output to serial port (serial0) and console (tty1);
* `root=/dev/nfs`: specifies that the root filesystem will be loaded via NFS;
* `nfsroot=10.0.7.1:/nfs,hard,nolock`: 
  - IP address of the NFS server and exported directory;
  - `hard`: specifies that operations should be retried on failure;
  - `nolock`: disables file locking (recommended for NFSv4);
* `rw`: mounts the root filesystem with read-write permissions;
* `ip=dhcp`: specifies that IP address should be obtained via DHCP;
* `rootwait`: waits until the root filesystem is ready.

At the very beginning of the `mount_raw_rpi4()` function, environment variables are initialized to select the bootable image:

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

The `find_name_image()` function checks if there are any suitable images available. If images exist, you'll be presented with a numbered list (1 to N) in the console. If you select an archived image:
- It will be unpacked;
- Environment variables will be configured for potential loading via `mount_raw_image()`.

I also have a cleanup function that restores the image's `config.txt` and `cmdline.txt` files to their original state. This is useful if you later decide to flash the image to an SD card using `dd` after manipulations - you never know what might happen.

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

Before restoring anything, remember to execute `poweroff` on the booted system and wait for the NFS root filesystem to unmount properly.

After shutting down the Raspberry Pi 4, you can safely unmount all mount points. But also don't forget to stop the Docker container - it runs in the VSCode terminal and waits for termination via Ctrl+C or `docker stop hash_container` (this is important to consider).

Next, call `restore_image_rpi4()`. If everything is OK, you can attempt to write the image. If it's an archived image, you'll need to manually move the file from `tmp_mount` to the default images directory for the `sdcard_deploy` function (I haven't automated this yet).

While at it, check if the `dtoverlay=vc4-kms-v3d` issue persists (or is it just my setup?). If the problem exists, you'll need a debug UART - no video output will be visible. Alternatively, you can directly modify **`config.txt`** on the SD card after copying the raw image using `dd`.


## Network Boot for Raspbian on Raspberry Pi 4 Board

So the top-level code for Raspbian network boot:

```lua
start_netboot_raspios() {
    set_env_raw_raspios
    stop_docker "dhcp_tftp_nfs:buster-slim"
    mount_raw_raspios && start_session_docker
}
```

next:

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

Here I modify the standard `cmdline.txt` on the FAT boot partition to this:

```lua
console=serial0,115200 console=tty1 root=/dev/nfs nfsroot=10.0.7.1:/nfs,hard,nolock,vers=3 rw ip=dhcp rootwait
```

Additionally, to ensure everything works smoothly, you need to modify the standard `/etc/fstab` in the Raspbian image:  
(Otherwise it won't work - it will keep checking, attempting to verify, and hang indefinitely)

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

But we'll outsmart it: comment out the `PARTUUID=` disks under root privileges. Later if needed, we can re-enable them, preserving the image's ability to be flashed to an SD card with `dd`:

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

Note: UART debugging is also enabled in `config.txt` - it can be connected to GPIO pins. This setting is restored to the original `Raspbian` (RaspiOS) configuration.


## Automated Analysis of Yocto Build Logs Using Deepseek Neural Network

The next function I need is accelerated analysis of build logs and fixing Yocto errors. For this, some neural network would be extremely useful to provide repair suggestions. Ideally, I want to pipe build logs directly into the neural network without intermediaries. 

Manually copying error walls from one console and pasting them into browser windows like chat.deepseek.com is terribly slow and exhausting. Let's begin:

Installing and running DeepSeek through Ollama proved remarkably simple. I remember spending half a day installing Stable Diffusion - dependencies here, components there. But here? Pure magic - completely hidden from the user, and truly awesome.

```lua
# the Model size 4.9 Гб and Ollama itself ~3 Гб
DEEPSEEK_MODEL="deepseek-r1:8b"
install_deepseek() {
    curl -fsSL https://ollama.com/install.sh | sh
    ollama serve
    ollama run ${DEEPSEEK_MODEL}
}
```

In my opinion, the local deepseek-r1 can also be used as a translator - very convenient. But for quality advice, you'll still need to visit chat.deepseek.com (or wherever you usually go).

The `curl` command is used to download the installation script from the specified URL:

* Option `-f` enables "fail silently";
* Option `-s` makes the request without a progress bar, while `-S` shows errors if anything goes wrong;
* Option `-L` (follow redirects) automatically redirects the request to a new URL if necessary.  
The result (`|`) is then piped to `sh`, which executes the downloaded script locally.

Next, the Ollama server starts and loads the selected model. On first run, the model is downloaded to your local machine.

And immediately, here's the code to remove Ollama and all its "models" - seen enough?:

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

Console launch of ollama that can be assigned to a button press:

```lua
run_deepseek() {
    ollama run ${DEEPSEEK_MODEL}
}
```

Here's what Yocto log analysis looks like in Deepseek. The key is keeping logs reasonably sized - if you spot a specific error, you can pass just that portion. Large logs will definitely overwhelm the neural network (some buffer will overflow and that's it - in my experience).

```lua
yocto_analyze_deepseek() {
  local cmd_runs="$1"
  DOCKER_DIR="docker/ubuntu_22_04"
  CONTAINER_NAME="ubuntu_22_04"
  cmd_init="cd /mnt/data; MACHINE=$YO_M source ./setup-environment build"
  start_cmd_docker "${cmd_init}; ${cmd_runs}" | ollama run ${DEEPSEEK_MODEL} 'analyze to check for errors'
}
```


## Side Effect of the Build: Network Booting Ubuntu ISO Distribution

So the top-level code that initiates network boot:

```lua
start_ubuntu_24_04() {
  IMAGE_NAME="ubuntu-24.04.2-desktop-amd64.iso"
  IMAGE_UBUNTU_URL="http://releases.ubuntu.com/24.04.2"
  DOCKER_DIR='docker/dhcp_tftp_nfs'
  stop_docker "dhcp_tftp_nfs:buster-slim"
  mount_raw_ubuntu && start_session_docker
}
```

The `mount_raw_ubuntu()` ISO image mounting is launched, and on success: a Docker console session starts.

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

The process here is similar to **`mount_raw_rpi4`**, with one key difference: I can't write directly to the ISO. Instead, I need to prepare:
- A boot menu
- Initial firmware (bootloader) for the network card: **`pxelinux.0`** in the TFTP server root

This bootloader is extracted from a separate `netboot.tar.gz` archive, which contains everything needed to display the boot menu.

I then add a menu entry to Ubuntu's standard Netboot configuration, placing it at the very bottom:

```lua
...
label ubuntu
menu label ^ubuntu-24.04.2-desktop-amd64
kernel ubuntu-24.04.2-desktop-amd64/vmlinuz
append initrd=ubuntu-24.04.2-desktop-amd64/initrd root=/dev/nfs netboot=nfs nfsroot=10.0.7.1:/nfs ip=dhcp nomodeset
```

The key here is selecting the correct kernel and initrd that match the same distribution version as the root filesystem you're loading via NFS. Also note: during the initial PXE boot stage, the system doesn't know about NFS and can't handle it, so the kernel and initrd must be on the TFTP server.

If you select the new menu entry, it will start booting `ubuntu-24.04.2-desktop-amd64`. Since this isn't the default option, you have only 5 seconds to make this selection.

To eliminate the graphical mode warning (on my 4K monitor, kernel boot logs appeared tiny), I added the `nomodeset` parameter separately. This disabled that extremely annoying window:

```
Oh no! Something has gone wrong
A problem has occured and the system can't recover
Please log out and try again
```

And finally, the magical "What do you want ..." window will appear. You can choose:

```
   Install Ubuntu
   Try Ubuntu
```

Selecting **Try Ubuntu** allows you to click the **Close** button and immerse yourself in a memory-resident live environment. This full bootable live image lets you test hardware "without leaving the metal," as they say. I won't explain the **Install Ubuntu** option - you already know it.

One thing I verified: Internet connectivity in Ubuntu works via WiFi while simultaneously using NFS for the root filesystem. During boot, our host (10.0.7.1) becomes the default gateway for NFS, but Ubuntu automatically handles routing adjustments when WiFi connects. Note: **Raspbian fails to do this**.

During `ubuntu-24.04.2-desktop-amd64.iso` installation to hard drive, the process aborted due to incorrect package hash checksums fetched via NFS. The ISO exceeds 5GB, and checksum verification likely failed somewhere. I quickly added support for **22.04** instead - which worked flawlessly. Keep this in mind.

```lua
    IMAGE_NAME="ubuntu-22.04.1-desktop-amd64.iso"
    #IMAGE_NAME="ubuntu-24.04.2-desktop-amd64.iso"
```


## The Most Beautiful Button for Elvis's Friends

You might ask: Why Elvis?

First, nearly every company has its RockStar(s) - archetypes holding everything together. They'll understand.  
Second, I sought the most valuable board within reach. At home? Only Banana Republic-grade cheap boards - not worthy. But at work? Found this gem right on the desktop. Worth two of my home PCs. Perfect. This is what we'll boot.

Mission: Conquer U-Boot with a single button press. The board from "Elvis" features the "Skif" processor. Actually two boards (debug + processor) working in tandem, so we'll treat them as one device to frustrate U-Boot.

Interestingly, the board manual lacks network boot documentation. Decided to fix that. Here's the Docker-launching function code for network boot:

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

Two boot modes are implemented here:

First mode: For firmware built from source using Buildroot - designed for developers.  
- Build firmware → Launch Docker → Initiate network boot on board (details below) → Boot board → Run tests  
- Always loads the latest build. If valid:  
  - SSH directly into the board from host  
  - Write `rootfs.tar.gz` to eMMC following Elvis documentation  
  (Full proper deployment)

Second mode ("Just looking"): When you need instant results without 4-5 hour builds. Load precompiled images from their website. 

Requires only three magical files (finally no external bootloaders!):

kernel, device Tree Blob (dtb) and root filesystem (already archived)  

```lua
local files=(
    "Image"
    "rootfs.tar.gz"
    "elvees/mcom03-elvmc03smarc-r1.0-elvsmarccb-r3.2.1.dtb"
)
```

Next, the process is straightforward:
- Provide the kernel to the TFTP server through the directory where everything is either built or downloaded
- Unpack the root filesystem at `/tmp/docker/nfs` as root

⚠️ Critical: File permissions must be preserved during extraction (as root ownership), otherwise:
  - "systemd" in the NFS-loaded rootfs will fail
  - Numerous components will break
  - Process permissions must be strictly maintained - no exceptions!

Archive extraction will prompt for the administrator password.  

For U-Boot, create a single configuration file with the standard name `pxelinux.cfg/default` in the TFTP server root directory:

Here's the configuration:

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

After copying this template, perform string replacements:

1. Replace `"IMAGE_DTB"` with:  
   `elvees/mcom03-elvmc03smarc-r1.0-elvsmarccb-r3.2.1.dtb`

2. Replace `"NFS_IP_ADDRESS"` with `10.0.7.1`  
   (value of `IP_TFTP` variable in `func.sh`)

On the Elvis Skif board itself:  
- Trigger U-Boot and request **network boot** using the engineering USB-TypeC cable  
- Connect this cable between your host computer and the board  

Then initiate boot using the following function:

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

This function only pretends to be bash - it's actually a hybrid. It encapsulates one language within another using EOF markers (start/end of file delimiters).  

Technically, it's a text section that:  
1. Saves to a uniquely named temporary file in `/tmp`  
2. Gets executed by bash  
3. Receives one environment variable: the NFS server IP (my TFTP/NFS server uses the same IP)  

I adore `expect` - it perpetually waits for text responses from any process you point it at.  

Here's the workflow:  
1. `expect` launches a terminal session via serial port (UART)  
2. Targets U-Boot (which we've interrupted)  
3. Passes the IP address for TFTP server access  
4. Initiates network boot mode  

U-Boot then:  
1. Requests boot configuration via TFTP  
2. Finds it at the standard default path `pxelinux.cfg/default`  
3. Loads the kernel specified in the configuration  
4. Loads the board's DTB  
5. Passes pre-configured kernel parameters  
6. Hands control to the kernel (mission complete)  

If successful:  
1. Kernel mounts NFS root filesystem  
2. User session starts (detected by "login:" prompt)  
3. `expect` makes its final move: switches to interactive mode  

That's it! Now you can enter username/password and work.  

To build firmware for the Skif board from source, use this function:

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

Building the Buildroot distribution here uses Elvis's Docker container. The process takes about 4-5 hours, depending on your computer's performance.

And finally, my most beautiful button looks like this:  
(admittedly not as gorgeous as a golden, but decent enough)

```json
"actionButtons": {
    "reloadButton": null,
    "loadNpmCommands": false,
    "commands": [
        {
            "name": "StartElveesSkif-24.06",
            "singleInstance": true,
            "color": "#00008b",
            "command": "cd .vscode/yo; source func.sh; start_elvees_skif_24_06"
        },
        {
            "name": "Elvees🖲Netboot",
            "singleInstance": true,
            "color": "#000000",
            "command": "cd .vscode/yo; source func.sh; start_elvees_skif_netboot"
        }
    ]
}
```

Instead of text labels, you can assign beautiful UTF-8 symbols to buttons. While the selection is limited, it's worth exploring. There's also a dedicated developer button:

```json
{
    "name": "Build🖲Elvees",
    "singleInstance": true,
    "color": "#007fff",
    "command": "cd .vscode/yo; source func.sh; build_elvees_skif_24_06"
},
```

The general workflow is as follows:

1. Connect the engineering USB-TypeC cable  
2. Connect the network cable from host to one of the board's ports  
3. Launch Docker (button: `StartElveesSkif-24.06`)  
4. Initiate U-Boot session (button: `Elvees🖲Netboot`)  
5. Power on the board  

## Embedding Buttons in VSCode as a Train Chain

I'll add buttons to the **"seunlanlege.action-buttons"** plugin using a "train chain" method to accommodate all functions. This works by having the last button in Menu1 switch to Menu2, and the final button in MenuN looping back to Menu1 (circular navigation). Here's an example implementation:

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
      "command": "cp -f .vscode/settings.json.Menu2 .vscode/settings.json; exit"
    }
  ]
}
```

And for the final "MenuN":

```json
...
{
  "name": "⮕ Menu1",
  "singleInstance": true,
  "color": "#000000",
  "command": "cp -f .vscode/settings.json.Menu1 .vscode/settings.json; exit"
}
```

I didn't like the circular method and settled on the classic approach instead - where you can always see which button row is active. Here's how it looks:

```dart
    #          BUILD   ▶Load
    # Build◀   LOAD    ▶Install
    # Load ◀   INSTALL
```

I'll have three menu levels total, implemented as separate files:

* settings.json.build
* settings.json.load
* settings.json.install

The button with capital letters always displays the current menu level, and can also trigger the appropriate action. For `BUILD`, it looks like this:

```json
{
  "name": "BUILD",
  "singleInstance": true,
  "color": "#000000",
  "command": "cd .vscode/yo; source func.sh; DOCKER_DIR='docker/ubuntu_22_04'; start_session_docker"
}
```

Well, that's roughly how it works. Why is this convenient?  
Because you can assign all your proprietary installers to buttons, keeping them always at hand. You can create any classification system with groups and subgroups - everything exactly how you like it.

To install the "vscode-yocto-helper" project, try running the command:

```bash
curl -fsSL https://raw.githubusercontent.com/berserktv/vscode-yocto-helper/refs/heads/master/install.sh | sh
```

Or view it this way:

```bash
    mkdir vscode-yocto-helper
    cd vscode-yocto-helper
    git clone https://github.com/berserktv/vscode-yocto-helper.git .vscode
    code .
```

So in my view, the result is "Network Boots" - I hadn't used NFS before and didn't realize how powerful it is. Just one recommendation: don't expose Docker in host mode to the internet, it's not secure.

This article is also written for **Margarita**, as an example of leveraging bash capabilities for practical solutions. When you have just a few Makefiles, zero C/C++ files, only pure bash in Docker, yet want to create something valuable.

## Postscript:

For half a year I chased every developer in my department - literally all two of them. I offered the button (still virtual), but they wouldn't take it. Said they're busy with boot processes, no time for buttons now. Well then, it's yours. As for me? I'm still sitting in a terminal, ebashe-ing in bashe, dreaming of **Lua** and building special-purpose images.