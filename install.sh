#!/bin/bash
##
# Variables
##
directory=${HOME}/runners
name=
group=Default
project=
repository=
token=
working_directory=_work
enable_service=false

##
# Function
##
function usage(){
    cat <<EOF
This script installs a azure pipelines agent.
  
Options:
  -d, --directory            Defines the install directory of a github action runner. Default value is ${HOME}/runners.
  -n, --name                 Defines name of a runner.
  -g, --group                Defines group of a runner.
  -g, --project              Defines project of a runner.
  -w, --working-directory    Defines working directory of a runner.
  -r, --repository           Defines url of a repository.
  -t, --token                Defines registration token for repository.
  -s, --service              Installs a runner as a service.
  -h, --help                 Shows this message.
  
Examples:
  $(dirname $0)/install.sh --name NAME --group GROUP --project PROJECT --repository REPO --token TOKEN
  $(dirname $0)/install.sh -n NAME -r REPO -t TOKEN
EOF
}

function parse_cmd_args() {
    args=$(getopt --options d:n:g:p:r:t:w:sh \
                  --longoptions directory:,name:,group:,project:,repository:,token:,working-directory:,service,help -- "$@")
    
    if [[ $? -ne 0 ]]; then
        echo "Failed to parse arguments!" && usage
        exit 1;
    fi

    while test $# -ge 1 ; do
        case "$1" in
            -h | --help) usage && exit 0 ;;
            -d | --directory) directory="$(eval echo $2)" ; shift 1 ;;
            -n | --name) name="$(eval echo $2)" ; shift 1 ;;
            -g | --group) group="$(eval echo $2)" ; shift 1 ;;
            -p | --project) project="$(eval echo $2)" ; shift 1 ;;
            -w | --working-directory) working_directory="$(eval echo $2)" ; shift 1 ;;
            -r | --repository) repository="$(eval echo $2)" ; shift 1 ;;
            -s | --service) enable_service=true ;;
            -t | --token) token="$(eval echo $2)" ; shift 1 ;;
            --) ;;
             *) ;;
        esac
        shift 1
    done 
}

function command_exists() {
    if ! command -v $1 2>&1 >/dev/null ; then
        echo "Please, install $1 via your package manager."
        exit 1
    fi
}

function detect_os() {
    os="LINUX"
    case "$(uname -s)" in
        "Darwin") os="MacOS" ;;
    esac
    echo ${os}
}

function get_log_level() {
    case $1 in
        ERROR) echo 1 ;;
        WARN) echo 2 ;;
        INFO) echo 3 ;;
        DEBUG) echo 4 ;;
    esac
}

function log() {
    log_level=${1}
    log_message=$2
    if [[ $(get_log_level ${LOG_LEVEL:-INFO}) -ge $(get_log_level $log_level) ]] ; then
        if [[ "$(detect_os)" == "MacOS" ]] ; then
            echo -e "$(date +"%Y-%m-%d %H:%M:%S") ${log_level}\t $log_message"
        else
            echo -e "$(date +"%Y-%m-%d %H:%M:%S.%3N") ${log_level}\t $log_message"
        fi
    fi
}

##
# Main
##
{

    parse_cmd_args "$@"

    command_exists curl
    command_exists python3

    download_url_praser=$(cat <<EOF
import sys
import json
import platform

if __name__ == "__main__":
    json_object = json.load(sys.stdin)
    if "assets" in json_object.keys() and len(json_object["assets"]) > 0:
        asset = json_object["assets"][0]
        print(asset.get("browser_download_url", ""))
    else:
        raise Exception(json_object.get("message", "Something went wrong"))
EOF
)

    asset_praser=$(cat <<EOF
import sys
import json
import platform

def normalize_os_n_arch():
    os_name = platform.system()
    if os_name == "Darwin":
        os_name = "osx"
    elif os_name == "Linux":
        os_name = "linux"
    elif os_name == "Windows":
        os_name = "win"
    else:
        raise Exception("OS {} is not supported yet.".format(os_name))
    arch = platform.machine().lower()
    if arch == "x86_64":
        arch = "x64"
    elif arch == "aarch64":
        arch = "arm64"
    return  "{}-{}".format(os_name, arch)

if __name__ == "__main__":
    os_n_arch = normalize_os_n_arch()
    try:
        for json_object in json.load(sys.stdin):
            if json_object["name"].startswith("pipelines-agent") and json_object["platform"] == os_n_arch:
                print(json_object.get("downloadUrl", ""))
    except:
        raise Exception(json_object.get("message", "Something went wrong"))
EOF
)

    if [[ "${name}" == "" ]] ; then
        echo "Please, define a name via --name NAME"
        exit 1
    fi
    
    if [[ "${repository}" == "" ]] ; then
        echo "Please, define an URL of a repository via --repository REPO"
        exit 1
    fi

    if [[ "${token}" == "" ]] ; then
        echo "Please, define a token via --token TOKEN"
        exit 1
    fi

    if [[ "${group}" == "" ]] ; then
        echo "Please, define a group via --group GROUP"
        exit 1
    fi

    if [[ "${project}" == "" ]] ; then
        echo "Please, define a project via --project PROJECT"
        exit 1
    fi

    runner_directory=${directory}/${name}
    if ! [ -d ${runner_directory} ] ; then
        mkdir -p ${runner_directory}
    fi
    
    download_urls=$(curl -s https://api.github.com/repos/microsoft/azure-pipelines-agent/releases/latest | python3 -c "${download_url_praser}")
    for download_url in $download_urls ; do
        asset_file_path=${runner_directory}/$(basename $download_url)
        log INFO "Starting to download asset file from ${download_url}"
        curl -s -L ${download_url} --output ${asset_file_path}
        log DEBUG "Downloaded asset file from ${download_url}"
        binary_download_url=$(cat ${asset_file_path} | python3 -c "${asset_praser}" )
        log INFO "Removing ${asset_file_path}"
        rm ${asset_file_path}
        log DEBUG "Removed ${asset_file_path}"
        file_path=${runner_directory}/$(basename ${binary_download_url})
        log INFO "Starting to download ${binary_download_url}"
        curl -s -L ${binary_download_url} --output ${file_path}
        log INFO "Unpacking ${file_path} to ${runner_directory}"
        tar xzf ${file_path} -C ${runner_directory}
        log DEBUG "Unpacked ${file_path} to ${runner_directory}"
        log INFO "Removing ${file_path}"
        rm ${file_path}
        log DEBUG "Removed ${file_path}"
        cd ${runner_directory}
        ./config.sh --unattended --url ${repository} --token ${token} \
                    --agent ${name} --auth PAT --replace --deploymentgroup --deploymentgroupname ${group} \
                    --work ${working_directory} --acceptTeeEula --projectname ${project}
        escaped_name=$(echo "${name}" | sed 's#\/#\\/#g')
        escaped_runner_directory=$(echo "${runner_directory}" | sed 's#\/#\\/#g')
        #if [ ${enable_service} == "true" ] && [ -d /etc/systemd/system ] ; then
        #    systemctl daemon-reload
        #    systemctl start azure-pipelines-${name}.service
        #    systemctl enable azure-pipelines-${name}.service
        #fi
    done
}
