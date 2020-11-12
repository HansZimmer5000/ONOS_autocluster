#!/bin/bash

#Some info from: https://github.com/ralish/bash-script-template/blob/stable/script.sh

combinedNetName="onos-net"
#atomixNetName="atomix-net"
creatorKey="creator"
creatorValue="onos-cluster-create"

# Set by bash_profile (if imported): https://github.com/opennetworkinglab/onos/blob/master/README.md#build-onos-from-source
ONOS_ROOT=${ONOS_ROOT:-./onos}
logs_and_configs_dir=${logs_and_configs_dir:-$PWD/../logs} # Default: /tmp
if ! [ -d $logs_and_configs_dir ]; then
    mkdir $logs_and_configs_dir
fi

atomixVersion="3.1.5"
atomixImage="atomix/atomix:$atomixVersion"
onosVersion="2.2.6"
onosImage="onosproject/onos:$onosVersion"
atomixNum=3
onosNum=3

customSubnet=172.20.0.0/16
customGateway=172.20.0.1

allocatedAtomixIps=()
allocatedOnosIps=()
atomixContainerNames=()
onosContainerNames=()

# Handling arguments, taken from (goodmami)
# https://gist.github.com/goodmami/f16bf95c894ff28548e31dc7ab9ce27b
die() { echo "$1"; exit 1; }

usage() {
  cat <<EOF
    Options:
      -h, --help                  display this help message
      -o, --onos-version          version for ONOS: e.g. 2.2.1
      -a, --atomix-version        version for Atomix: e.g 3.1.5
      -i, --atomix-num            number of Atomix containers
      -j, --onos-num              number of ONOS containers
EOF
}

parse_params() {
  # Option parsing
  while [ $# -gt 0 ]; do
      case "$1" in
          --*=*)               a="${1#*=}"; o="${1#*=}"; shift; set -- "$a" "$o" "$@" ;;
          -h|--help)           usage; exit 0; shift ;;
          -a|--atomix-version) atomixVersion="$2"; shift 2 ;;
          -o|--onos-version)   onosVersion="$2"; shift 2 ;;
          -i|--atomix-num)     atomixNum="$2"; shift 2 ;;
          -j|--onos-num)       onosNum="$2"; shift 2 ;;
          --)                  shift; break ;;
          -*)                  usage; die "Invalid option: $1" ;;
          *)                   break ;;
      esac
  done
  echo "atomix-version: $atomixVersion"
  echo "onos-version: $onosVersion"
  echo "atomix-containers: $atomixNum"
  echo "onos-containers: $onosNum"
  echo "subnet: $customSubnet"
}

containsElement () {
  local e match="$1"
  shift
  for e; do [[ $e == "$match" ]] && return 0; done
  return 1
}

create_net_ine(){
  if [[ ! $(sudo docker network ls --format "{{.Name}}" --filter label=$creatorKey=$creatorValue) ]];
  then
      # --label "$creatorKey=$creatorValue"
      sudo docker network create --driver bridge --subnet $customSubnet --gateway $customGateway $combinedNetName >/dev/null
      echo "Creating Docker network $combinedNetName ..."
  fi
}

pull_if_not_present(){
  echo "Pulling $1"
  if [[ "$(sudo docker images --format '{{.Repository}}:{{.Tag}}')" != *"$1"* ]]; then
    sudo docker pull $1 >/dev/null
  fi
}

clone_onos(){
  if [ ! -d "$HOME/onos" ] ; then
    cd
    git clone https://gerrit.onosproject.org/onos
  fi

}

create_atomix(){
  emptyArray=()
  for (( i=1; i<=$atomixNum; i++ ))
  do
    $ONOS_ROOT/tools/test/bin/atomix-gen-config "atomix-$i" $logs_and_configs_dir/atomix-$i.conf atomix-1 atomix-2 atomix-3  >/dev/null
    
    sudo docker run -d \
      --name atomix-$i \
      --hostname atomix-$i \
      --net $combinedNetName \
      -v $logs_and_configs_dir/atomix-$i.conf:/opt/atomix/conf/atomix.conf \
      $atomixImage >/dev/null
    echo "Creating atomix-$i container"
    atomixContainerNames+=("atomix-$i")
  done
}

create_onos(){
  emptyArray=()
  for (( i=1; i<=$onosNum; i++ ))
  do
    echo "Starting onos$i container"
    $ONOS_ROOT/tools/test/bin/onos-gen-config onos$i $logs_and_configs_dir/cluster-$i.json -n atomix-1 atomix-2 atomix-3 >/dev/null

    sudo docker run -d \
      --name onos$i \
      --hostname onos$i \
      --net $combinedNetName \
      -v $logs_and_configs_dir/cluster-$i.json:/root/onos/config/cluster.json \
      -e ONOS_APPS="drivers,openflow-base,netcfghostprovider,lldpprovider,gui2" \
      $onosImage >/dev/null

    onosContainerNames+=("onos$i")
  done
}

# $@ = Each parameter is one container name
save_docker_logs(){
  for name in $@
  do
    # Process "docker logs -f" will end when container stops
    nohup docker logs -f $name >$logs_and_configs_dir/$name.log 2>&1 &
  done
}

function main() {
    parse_params "$@"

    # Prepare
    pull_if_not_present $atomixImage
    pull_if_not_present $onosImage
    clone_onos
    create_net_ine

    # Start & Setup
    create_atomix
    create_onos
    save_docker_logs ${atomixContainerNames[@]} ${onosContainerNames[@]}
}

# Make it rain
main "$@"
