#!/bin/bash
set -eo pipefail

ZARF_REPO='defenseunicorns/zarf'
ZARF_PLATFORM='amd64'
 
install_zarf_cli() {
   ZARF_VERSION=$1
   echo "Installing Zarf CLI Package"

   wget -nv "https://github.com/${ZARF_REPO}/releases/download/${ZARF_VERSION}/zarf_${ZARF_VERSION}_Linux_${ZARF_PLATFORM}"
   chmod +x zarf_${ZARF_VERSION}_Linux_${ZARF_PLATFORM}
   mv zarf_${ZARF_VERSION}_Linux_${ZARF_PLATFORM} /usr/local/bin/zarf
   zarf version
}

install_init_package() {
   ZARF_VERSION=$1
   echo "Installing Zarf Initialization Package"
   
   curl -fL "https://github.com/${ZARF_REPO}/releases/download/${ZARF_VERSION}/zarf-init-amd64-${ZARF_VERSION}.tar.zst" -o "zarf-init-$ZARF_PLATFORM.tar.zst"
}

zarfify_cluster(){
   ZARF_VERSION=$1
   ZARF_COMPONENTS='git-server'
   NAMESPACE_NAME='zarf'
   kubectl get ns
   echo "Checking if the ${NAMESPACE_NAME} namespace exists in the cluster"
   NS=$(kubectl get namespace $NAMESPACE_NAME --ignore-not-found);
        
   if [[ "$NS" ]]; then
     echo "Skip initializing zarf as namespace $NAMESPACE_NAME - already exists";
   else
     echo "Setting up Zarf";
     install_init_package ${ZARF_VERSION}
     ./zarf init --components ${ZARF_COMPONENTS} --confirm
   fi;
}

error() {
   echo $1>&2
   usage
   exit 1
}

usage() {
cat <<EOM
Usage:
  zarf-install.sh -v v0.23.2 -t cli
Flags:
  -h,                 this info
  -v,                 target zarf version
  -t,                 Installation type. Supported options are cli or init_cluster or init_package (defaults to cli)
EOM
}

if [ -z $1 ]
then
  error "No arguments specified"
fi

version='v0.23.2'
install_type='cli'

while getopts h:v:t: flag
do
    case "${flag}" in
        h) usage;;
        v) version=${OPTARG};;
        t) install_type=${OPTARG};;
        *)
        error "Unsuported argument error: ${flag}, ${OPTARG}"
        ;;
    esac
done

echo "Executing install type: ${install_type} on version: ${version}"

if [ -z version ]
then
  error "no version is specified"
elif [ $install_type == 'cli' ]
then
  install_zarf_cli $version
elif [ $install_type == 'init_package' ]
then
  install_init_package $version
elif [ $install_type == 'init_cluster' ]
then
  zarfify_cluster $version
else  
  error "invalid option: $*"
fi