#!/usr/bin/env bash

set -Eeuo pipefail
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)

# Read unique and confidential information from .env
source "${script_dir}/.env"
API_URL='https://api.zerossl.com/certificates'

usage() {
  cat <<EOF
Usage: $(basename "${BASH_SOURCE[0]}") [-h] [-v] arg1 [arg2...]

Script description here.

Available options:

-h, --help      Print this help and exit
-v, --verbose   Print script debug info
EOF
  exit
}

gen_csr_conf() {
  config=$(
    cat <<EOF
[ req ]
default_bits           = 2048  # RSA key size
encrypt_key            = no  # Protect private key
default_md             = sha256  # MD to use
utf8                   = yes  # Input is UTF-8
string_mask            = utf8only  # Emit UTF-8 strings
prompt                 = no  # Prompt for DN
distinguished_name     = req_distinguished_name  # DN template
req_extensions         = v3_req  # Desired extensions

[ req_distinguished_name ]
countryName            = ${SUB_C}  # ISO 3166
stateOrProvinceName    = ${SUB_ST}
localityName           = ${SUB_L}
organizationName       = ${SUB_O}
organizationalUnitName = ${SUB_OU}
commonName             = ${CERT_NAME}  # Should match a SAN under alt_names

[ v3_req ]
basicConstraints       = CA:FALSE
keyUsage               = critical,digitalSignature,keyEncipherment
extendedKeyUsage       = serverAuth,clientAuth
subjectKeyIdentifier   = hash
subjectAltName         = @alt_names

[ alt_names ]
DNS.1                  = ${CERT_NAME}
EOF
  )

  CN_LIST=("${CERT_NAME}")
  VE_LIST=("${EMAIL}@${CERT_NAME}")

  # make SANs field configuration
  shift
  if [[ "$#" -ne 0 ]]; then
    i=2
    while [ "$#" -gt 0 ]; do
      config=$(
        echo "${config}"
        echo "DNS.$i                  = $1.${DOMAIN}"
      )
      CN_LIST+=("$1.${DOMAIN}")
      VE_LIST+=("${EMAIL}@$1.${DOMAIN}")
      shift
      ((i++))
    done
  fi

  return 0
}

get_enviroment() {
  if [[ -z "${ZEROSSL_KEY+UNDEF}" ]]; then
    die "Variable ZEROSSL_KEY is not defined."
  else
    ACS_KEY="access_key=${ZEROSSL_KEY}"
  fi
  if [[ -z "${DOMAIN+UNDEF}" ]]; then
    die "Variable DOMAIN is not defined."
  fi
  CERT_DIR="${CERT_DIR:-.}"
  SUB_C="${SUB_C:-JP}"
  SUB_ST="${SUB_ST:-Tokyo}"
  SUB_L="${SUB_L:-Chuo-ku}"
  SUB_O="${SUB_O:-MyCompany}"
  SUB_OU="${SUB_OU:-MyDivision}"
  EMAIL="${EMAIL:-webmaster}"

  CL_CMD="/usr/bin/curl -s -S -L"
}

msg() {
  echo >&2 -e "${1-}"
}

die() {
  local msg=$1
  local code=${2-1} # default exit status 1
  msg "$msg"
  exit "$code"
}

parse_params() {
  while (($# > 0)); do
    case "${1-}" in
    -h | --help) usage ;;
    -v | --verbose) set -x ;;
    -?*) die "Unknown option: $1" ;;
    *) break ;;
    esac
    shift
  done

  args=("$@")

  # check required arguments
  [[ ${#args[@]} -eq 0 ]] && die "Missing script arguments"

  return 0
}

main() {
  # take CN from params
  CERT_NAME="$1"."${DOMAIN}"
  CERT_PATH="${CERT_DIR}/${CERT_NAME}"

  # Check and create the store directory.
  if [[ ! -d "${CERT_PATH}" ]]; then
    mkdir -p $CERT_PATH
  else
    if [[ -n "$(ls -A ${CERT_PATH} >&/dev/null)" ]]; then
      die "Script terminated. ${CERT_PATH} already exists."
    fi
  fi
  cd "${CERT_PATH}"

  # Generate a Certificate Signing Request (CSR) configration
  gen_csr_conf "${args[@]}"

  # Generate CSR and Private Key
  openssl req -new -newkey rsa:2048 -nodes -sha256 -out "${CERT_NAME}.csr" \
    -keyout "${CERT_NAME}.key" \
    -config <(echo "${config}") \
    &>/dev/null

  # Draft certificate at ZeroSSL
  backup=$IFS
  resp=$(${CL_CMD} -X POST "${API_URL}"?"${ACS_KEY}" \
    --data-urlencode certificate_csr@"${CERT_NAME}".csr \
    -d certificate_domains="$(
      IFS=","
      echo "${CN_LIST[*]}"
    )" \
    -d certificate_validity_days=90)
  IFS=$backup

  # Extract ID parameters from ZeroSSL response
  ID=$(echo "${resp}" | jq -r '.id')

  # Configure the domain verification method.
  backup=$IFS
  ${CL_CMD} -X POST "${API_URL}"/"${ID}"/challenges?"${ACS_KEY}" \
    -d validation_method=EMAIL \
    -d validation_email="$(
      IFS=","
      echo "${VE_LIST[*]}"
    )" \
    -o "${CERT_NAME}".vald
  IFS=$backup

  # Waiting for domain verification
  until [[ "$(${CL_CMD} "${API_URL}"/"$ID"/status?"${ACS_KEY}" |
    jq '.validation_completed')" == 1 ]]; do
    sleep 30
  done

  # Wait for cert to be issued
  sleep 30

  # Get the cert
  ${CL_CMD} "${API_URL}"/"${ID}"/download/return?"${ACS_KEY}" |
    jq -r '."certificate.crt"' >"${CERT_NAME}".crt

  return 0
}

# Main body of script starts here
parse_params "$@"
get_enviroment
main "${args[@]}"
exit 0

