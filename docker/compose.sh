#!/bin/bash
set -eo pipefail

COMPOSE_FILE=${COMPOSE_FILE:-docker-compose.yml}
COMPOSE_PROJECT_DIRECTORY=${COMPOSE_PROJECT_DIRECTORY:-$(dirname $COMPOSE_FILE)}
COMPOSE_PROJECT_NAME=${COMPOSE_PROJECT_NAME:-system}

PROGRAM="${PROGRAM:-/usr/bin/system-docker-compose}"
DOCKER="${DOCKER:-/usr/bin/docker}"
MONITDIR="/monit"
MONITCFG="${MONITCFG:-}"        # system-docker-compose
MONITGROUP="${MONITGROUP:-}"    # system-docker-compose


###

# Load OCI images
load_oci_images() {
    local image

    pushd ${ENTRYPOINT} >/dev/null
        for image in $(ls)
        do
            case "${image}" in
                *.tgz)
                    echo "Loading ${image}"
                    echo ${DOCKER} load --input "${image}"
                ;;
                *.tar.gz)
                    echo "Loading ${image}"
                    echo ${DOCKER} load --input "${image}"
                ;;
                *.tar)
                    echo "Loading ${image}"
                    echo ${DOCKER} load --input "${image}"
                ;;
                *)
                    echo "Ignoring image ${image} ..."
                ;;
            esac
        done
    popd >/dev/null
}


# Create/delete monit conf
manage_monit() {
    local action="${1}"

    local services
    local service
    local key
    local container
    local monitcfg="${MONITDIR}/${MONITCFG}"

    if [ -z "${monitcfg}" ] || [ -z "${MONITGROUP}" ]
    then
        [ -r "${monitcfg}" ] && rm -f "${monitcfg}"
        return 0
    fi
    [ -d "${MONITDIR}" ] || mkdir -p "${MONITDIR}"
    case "${action}" in
    start|reload)
        if services=$(docker-compose config 2>/dev/null | yq -jr '.services | to_entries | map(select(.value.labels!=null and .value.container_name!=null) | select((.value.labels | keys | index("system")) and .value.labels.system)) | .[] |  .key, ":", .value.container_name, "\n"')
        then
            echo "# Autogenerated file by $0 at $(date)" > "${monitcfg}"
            for service in ${services}
            do
                key="${service%:*}"
                container="${service#*:}"
                cat >> "${monitcfg}" <<-EOF
				check program docker.${key} with path "/bin/bash -eo pipefail -c '${DOCKER} top ${container} | tail -n +2'"
				if status != 0 for 3 cycles then alert
				if status != 0 for 6 cycles then exec "${PROGRAM} reload"
				depends on docker
				group system
				group docker
				group ${MONITGROUP}
				
				EOF
            done
        else
            echo "Error getting list of docker-compose services: docker-compose config" >&2
            return 1
        fi
    ;;
    stop)
        [ -r "${monitcfg}" ] && rm -f  "${monitcfg}"
    ;;
    esac
}


case "${1}" in
    start)
        load_oci_images
        docker-compose rm -v --force
        docker-compose pull --quiet
        docker-compose up -d --no-color --remove-orphans && manage_monit ${1}
        ;;
    reload)
        docker-compose pull --quiet
        docker-compose build --pull
        docker-compose up -d --no-color --remove-orphans && manage_monit ${1}
        ;;
    stop)
        manage_monit ${1}
        docker-compose down
        ;;
    load)
        load_oci_images
        ;;
    status)
        docker-compose ps
        ;;
    top)
        docker-compose top
        ;;
    run)
        shift
        docker-compose "$@"
        ;;
    help|*)
        echo "Usage: [ start | reload | stop | status | load | run <list-docker-compose-options> ]"
        echo "  docker-compose wrapper to manage 'system' stack in <stackdir> folder"
        echo "  Default <stackdir> folder: ${COMPOSE_PROJECT_DIRECTORY}"
        echo "  Settings in <stackdir> (${COMPOSE_PROJECT_DIRECTORY}): ${COMPOSE_FILE}"
        echo
        ;;
esac

