#!/usr/bin/env bashio
CONFIG_PATH=/data/options.json

[ ! -d "${LE_CONFIG_HOME}" ] && mkdir -p "${LE_CONFIG_HOME}"

if [ ! -f "${LE_CONFIG_HOME}/account.conf" ]; then
    bashio::log.info "Copying the default account.conf file"
    cp /default_account.conf "${LE_CONFIG_HOME}/account.conf"
fi

ACCOUNT_EMAIL=$(bashio::config 'accountemail')
DOMAINS=$(bashio::config 'domains')
DNS_PROTO=$(bashio::config 'dns')
DNS_ENV_OPTIONS=$(jq -r '.dnsEnvVariables |map("export \(.name)=\(.value|tojson)")|.[]' $CONFIG_PATH)
KEY_LENGTH=$(bashio::config 'keylength')
FULLCHAIN_FILE=$(bashio::config 'fullchainfile')
KEY_FILE=$(bashio::config 'keyfile')
SERVER=$(bashio::config 'server')

source <(echo ${DNS_ENV_OPTIONS});

bashio::log.info "Registering account"
acme.sh --register-account -m ${ACCOUNT_EMAIL}

bashio::log.info "Issuing certificate for domain: ${DOMAINS[*]}"

function issue {
    # Issue the certificate exit corretly if is not time to renew
    local RENEW_SKIP=2
    local DOMAIN_ARG=$(printf -- "--domain %s " "${DOMAINS[@]}")
    acme.sh --issue ${DOMAIN_ARG} \
        --keylength ${KEY_LENGTH} \
        --dns ${DNS_PROTO} \
        --server ${SERVER} \
        || { ret=$?; [ $ret -eq ${RENEW_SKIP} ] && return 0 || return $ret ;}
}

issue

bashio::log.info "Installing certificate to: /ssl"
KEY_ARG=$( [[ ${KEY_LENGTH} == ec-* ]] && echo '--ecc' || echo '' )
acme.sh --install-cert --domain ${DOMAINS[0]} \
    ${KEY_ARG} \
    --key-file       "/ssl/${KEY_FILE}" \
    --fullchain-file "/ssl/${FULLCHAIN_FILE}"


bashio::log.info "All ok, running cron to automatically renew certificate"
trap "echo stop && killall crond && exit 0" SIGTERM SIGINT
crond && while true; do sleep 1; done;
