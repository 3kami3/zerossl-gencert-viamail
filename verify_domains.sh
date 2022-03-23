#!/bin/bash

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)

CL_CMD="/usr/bin/curl -s -S -L"

FROM1_MATCH_PATTERN='^"ZeroSSL"[^\S]*<noreply@trust-provider.com>$'
FROM2_MATCH_PATTERN='^no_reply_support@trust-provider.com .*$'
SUB_MATCH_PATTERN='^Verify Domains[^\S]*\(reference #[0-9]*\)$'

VERIFY_URL='https://secure.trust-provider.com/products/EnterDCVCode2'
ORD_MATCH_PATTERN='^https://secure.trust-provider.com/products/EnterDCVCode'
KEY_MATCH_PATTERN='/following key:$/{n;n;p}'

lines=$(cat)  # Standard Inputs

from1=$(echo "${lines}" | grep "^From:" | sed -e "s/^From: \(.*\)/\1/")
from2=$(echo "${lines}" | grep "^From " | sed -e "s/^From \(.*\)/\1/")
subject=$(echo "${lines}" | grep "^Subject:" | sed -e "s/^Subject: \(.*\)/\1/")

if [[ ! "${from1}" =~ ${FROM1_MATCH_PATTERN} ||
    ! "${from2}" =~ ${FROM2_MATCH_PATTERN} ||
    ! "${subject}" =~ ${SUB_MATCH_PATTERN} ]]; then
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] doesn't match" >>"${script_dir}/vd.log"
    exit 0 # doesn't match
fi

order_number=$(echo "${lines}" | grep "${ORD_MATCH_PATTERN}" | sed -e "s/.*orderNumber=\([0-9]*\)$/\1/")
verify_key=$(echo "${lines}" | sed -n "${KEY_MATCH_PATTERN}")

# Validate certificate at ZeroSSL(trust-provider.com)
echo "[$(date +"%Y-%m-%d %H:%M:%S")] ${CL_CMD} -X POST -d \"orderNumber=${order_number}&postPaymentPage=N&dcvCode=${verify_key}\" -o /dev/null ${VERIFY_URL}" >>"${script_dir}/vd.log"
${CL_CMD} -X POST -d "orderNumber=${order_number}&postPaymentPage=N&dcvCode=${verify_key}" -o /dev/null "${VERIFY_URL}" >>"${script_dir}/vd.log" 2>&1
exit 0

