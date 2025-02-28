#!/usr/bin/env bash

# Script atualizado para API v3 da Raydium - Pools AMM V3 com nomes, APR diário e ordenação

# Ativar depuração opcional (DEBUG=true)
if [ "${DEBUG}" = "true" ]; then
    set -x
fi

# Dependências obrigatórias
command -v curl >/dev/null 2>&1 || { echo "Este script requer curl. Instale-o primeiro."; exit 1; }
command -v jq   >/dev/null 2>&1 || { echo "Este script requer jq. Instale-o primeiro."; exit 1; }

# Definição da API v3 da Raydium
API_POOLS="https://api-v3.raydium.io/pools/info/list"
API_TOKENS="https://api-v3.raydium.io/mint/list"

# Criar arquivos temporários
TEMP_POOLS="$(mktemp /tmp/raydium_v3_pools.XXXXXX)"
TEMP_TOKENS="$(mktemp /tmp/raydium_v3_tokens.XXXXXX)"
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

# Definição do campo de ordenação e tipo
ORDER_BY="${ORDER_BY:-fee24h}"  # Padrão: ordenar por fee24h
SORT_TYPE="desc"  # Padrão: ordenação decrescente

# Buscar lista de tokens (nomes e símbolos)
log_debug "Buscando lista de tokens da API v3 em: $API_TOKENS"
if curl -s --fail --show-error -o "$TEMP_TOKENS" "$API_TOKENS"; then
    log_debug "Lista de tokens carregada com sucesso."
else
    log_debug "Erro ao buscar tokens da API v3."
    rm -f "$TEMP_TOKENS"
fi

# Buscar pools da API já ordenados
log_debug "Buscando pools da API v3 ordenados por $ORDER_BY ($SORT_TYPE)"
if ! curl -s --fail --show-error -o "$TEMP_POOLS" "$API_POOLS?poolType=all&poolSortField=$ORDER_BY&sortType=$SORT_TYPE&pageSize=1000&page=1"; then
    log_debug "Erro ao buscar pools da API v3."
    exit 1
fi

# Contar número de pools retornados
DATA_COUNT="$(jq '.data | length' "$TEMP_POOLS" 2>/dev/null)"
if [ -z "$DATA_COUNT" ] || [ "$DATA_COUNT" -eq 0 ]; then
    log_debug "Nenhum pool encontrado na API."
    exit 1
fi

log_debug "Total de pools encontrados na API: $DATA_COUNT"

# Definição de filtros mínimos
MIN_LIQUIDITY=100000
MIN_VOLUME_24H=1000000
MIN_APR_24H=600
LC_NUMERIC=C MIN_APR_DECIMAL="$(awk "BEGIN {print $MIN_APR_24H / 100}")"

log_debug "Filtrando pools com Liquidez >= USD $MIN_LIQUIDITY, Volume 24h >= USD $MIN_VOLUME_24H e APR 24h >= $MIN_APR_24H%..."

# Obter nome do token a partir do mint
get_token_name() {
    local token_id="$1"
    if [ -f "$TEMP_TOKENS" ]; then
        jq -r --arg token_id "$token_id" '.mintList[] | select(.address == $token_id) | .symbol' "$TEMP_TOKENS" | head -n 1
    else
        echo "N/A"
    fi
}

# Processar pools filtrados
FILTERED_POOLS="$(
    jq -r --argjson min_liq "$MIN_LIQUIDITY" \
    --argjson min_vol "$MIN_VOLUME_24H" \
    --argjson min_apr "$MIN_APR_DECIMAL" \
    '.data[] |
    select(
        (.liquidityUSD // 0) >= $min_liq and
        (.volume24hUSD // 0) >= $min_vol and
        ((.apr24h // 0) * 100) >= $min_apr
    ) |
    [ (.baseMint // "N/A"),
      (.quoteMint // "N/A"),
      (.liquidityUSD // 0),
      (.volume24hUSD // 0),
      ((.apr7d // 0) * 100),  # APR semanal convertido para %
      ((.apr24h // 0) * 100), # APR diário convertido para %
      (.fee24hUSD // 0),
      (.poolId // "N/A") ] |
    join("|")' "$TEMP_POOLS"
)"

# Contar número de pools filtrados
FILTERED_COUNT=$(echo "$FILTERED_POOLS" | wc -l)
log_debug "Total de pools filtrados: $FILTERED_COUNT"

# Exibir cabeçalho
echo "---------------------------------------------------------------------------------------------------------------------------------"
echo " Pool Name            | Liquidez (USD) | Volume 24h (USD) | APR 7d (%) | APR 1d (%) | Fee 24h (USD) | Pool ID"
echo "---------------------------------------------------------------------------------------------------------------------------------"

# Exibir pools filtrados, ordenados já na API
echo "$FILTERED_POOLS" \
    | while IFS='|' read -r baseMint quoteMint tvl volume24h apr7d apr1d fee24h pool_id; do
        baseName="$(get_token_name "$baseMint")"
        quoteName="$(get_token_name "$quoteMint")"
        pool_name="${baseName}/${quoteName}"
        [[ -z "$pool_name" || "$pool_name" = "N/A/N/A" ]] && pool_name="Sem Nome"

        tvl_formatted="$(format_number "$tvl")"
        volume24h_formatted="$(format_number "$volume24h")"
        apr7d_formatted="$(printf "%.2f" "$apr7d")"
        apr1d_formatted="$(printf "%.2f" "$apr1d")"
        fee24h_formatted="$(format_number "$fee24h")"

        printf "%-20s | %15s | %15s | %10s | %10s | %15s | %-40s\n" \
               "$pool_name" \
               "$tvl_formatted" \
               "$volume24h_formatted" \
               "$apr7d_formatted" \
               "$apr1d_formatted" \
               "$fee24h_formatted" \
               "$pool_id"
    done

echo "---------------------------------------------------------------------------------------------------------------------------------"
echo "Total de pools filtrados: $FILTERED_COUNT"
log_debug "Script concluído em $(date)"
