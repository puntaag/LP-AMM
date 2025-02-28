#!/usr/bin/env bash

# Script atualizado para listar pools de liquidez da Raydium AMM V3 com APR diário e total de pools filtrados.
# Agora busca corretamente os nomes dos tokens e permite ordenação por diferentes critérios.

# Ativar modo de depuração opcional (DEBUG=true)
if [ "${DEBUG}" = "true" ]; then
    set -x
fi

# Dependências obrigatórias
command -v curl >/dev/null 2>&1 || { echo "Este script requer curl. Instale-o primeiro."; exit 1; }
command -v jq   >/dev/null 2>&1 || { echo "Este script requer jq. Instale-o primeiro."; exit 1; }

# URLs da API
API_POOLS="https://api.raydium.io/v2/ammV3/ammPools"
API_TOKENS="https://api.raydium.io/v2/main/tokenList"  # Endpoint correto

# Criar arquivos temporários
TEMP_POOLS="$(mktemp /tmp/raydium_ammv3_pools.XXXXXX)"
TEMP_TOKENS="$(mktemp /tmp/raydium_ammv3_tokens.XXXXXX)"
trap 'rm -f "$TEMP_POOLS" "$TEMP_TOKENS"' EXIT

# Função de depuração
log_debug() {
    echo "[DEBUG] $1" >&2
}

# Formatação de números para leitura
format_number() {
    local num="${1%.*}"
    LC_NUMERIC=en_US.UTF-8 printf "%'d" "$num" 2>/dev/null || printf "%d" "$num"
}

# Buscar pools na API
log_debug "Buscando dados da API em: $API_POOLS"
if ! curl -s --fail --show-error -o "$TEMP_POOLS" "$API_POOLS"; then
    log_debug "Erro ao buscar pools da API."
    exit 1
fi

# Buscar lista de tokens na API
log_debug "Buscando lista de tokens da API em: $API_TOKENS"
if ! curl -s --fail --show-error -o "$TEMP_TOKENS" "$API_TOKENS"; then
    log_debug "Erro ao buscar tokens da API."
    exit 1
fi

# Contar número de pools retornados
DATA_COUNT="$(jq '.data | length' "$TEMP_POOLS" 2>/dev/null)"
if [ -z "$DATA_COUNT" ] || [ "$DATA_COUNT" -eq 0 ]; then
    log_debug "Nenhum pool encontrado na API."
    exit 1
fi

log_debug "Total de pools encontrados na API: $DATA_COUNT"

# Parâmetros de filtro
MIN_LIQUIDITY=100000
MIN_VOLUME_24H=1000000
MIN_APR_24H=600
LC_NUMERIC=C MIN_APR_DECIMAL="$(awk "BEGIN {print $MIN_APR_24H / 100}")"

log_debug "Filtrando pools com Liquidez >= USD $MIN_LIQUIDITY, Volume 24h >= USD $MIN_VOLUME_24H e APR 24h >= $MIN_APR_24H%..."

# Mapeamento de ordenação (padrão: Fee)
ORDER_BY="${ORDER_BY:-fee}"
case "$ORDER_BY" in
    liquidez)  ORDER_COLUMN=2 ;;
    volume)    ORDER_COLUMN=3 ;;
    apr)       ORDER_COLUMN=4 ;;
    apr1d)     ORDER_COLUMN=5 ;;
    fee)       ORDER_COLUMN=6 ;;
    *)         ORDER_COLUMN=6 ;;  # Padrão: ordenar por Fee
esac

# Obter o nome dos tokens a partir de seus IDs
get_token_name() {
    local token_id="$1"
    jq -r --arg token_id "$token_id" '.data[] | select(.mint == $token_id) | .symbol' "$TEMP_TOKENS" | head -n 1
}

# Processar pools filtrados
FILTERED_POOLS="$(
    jq -r --argjson min_liq "$MIN_LIQUIDITY" \
    --argjson min_vol "$MIN_VOLUME_24H" \
    --argjson min_apr "$MIN_APR_DECIMAL" \
    '.data[] |
    select(
        (.tvl // 0) >= $min_liq and
        (.day.volume // 0) >= $min_vol and
        ((.day.apr // 0) * 100) >= $min_apr
    ) |
    [ (.baseMint // "N/A"),
      (.quoteMint // "N/A"),
      (.tvl // 0),
      (.day.volume // 0),
      ((.day.apr // 0) * 100),
      ((.day.apr24h // 0) * 100),
      (.day.volumeFee // 0),
      (.id // "N/A") ] |
    join("|")' "$TEMP_POOLS"
)"

# Contar número de pools filtrados
FILTERED_COUNT=$(echo "$FILTERED_POOLS" | wc -l)
log_debug "Total de pools filtrados: $FILTERED_COUNT"

# Exibir cabeçalho
echo "----------------------------------------------------------------------------------------------------------------"
echo " Pool Name          | Liquidez (USD) | Volume 24h (USD) | APR 24h (%) | APR 1d (%) | Fee 24h (USD) | Pool ID"
echo "----------------------------------------------------------------------------------------------------------------"

# Exibir pools filtrados, ordenados pela métrica desejada
echo "$FILTERED_POOLS" \
    | while IFS='|' read -r baseMint quoteMint tvl volume24h apr24h apr1d fee24h pool_id; do
        pool_name="$(get_token_name "$baseMint") / $(get_token_name "$quoteMint")"
        [[ -z "$pool_name" ]] && pool_name="Sem Nome"
        tvl_formatted="$(format_number "$tvl")"
        volume24h_formatted="$(format_number "$volume24h")"
        apr24h_formatted="$(printf "%.2f" "$apr24h")"
        apr1d_formatted="$(printf "%.2f" "$apr1d")"
        fee24h_formatted="$(format_number "$fee24h")"

        printf "%-20s | %15s | %15s | %10s | %10s | %15s | %-40s\n" \
               "$pool_name" \
               "$tvl_formatted" \
               "$volume24h_formatted" \
               "$apr24h_formatted" \
               "$apr1d_formatted" \
               "$fee24h_formatted" \
               "$pool_id"
    done | sort -t'|' -k"$ORDER_COLUMN" -nr

echo "----------------------------------------------------------------------------------------------------------------"
echo "Total de pools filtrados: $FILTERED_COUNT"
log_debug "Script concluído em $(date)"
