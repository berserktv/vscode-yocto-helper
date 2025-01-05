#!/bin/bash
this_f=$(readlink -f "$0")
this_d=$(dirname "$this_f")
source $this_d/func.sh
sdcard_deploy
