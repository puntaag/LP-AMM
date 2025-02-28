#!/usr/bin/env bash

# Script para listar pools de liquidez da Raydium (AMM V3) com dados detalhados.
# Uso: 
#   ORDER_BY=fee ./raydium_ammv3_pools.sh
#   ORDER_BY=apr ./raydium_ammv3_pools.sh
#   ORDER_BY=apr1d ./raydium_ammv3_pools.sh
#   ORDER_BY=liquidez ./raydium_ammv3_pools.sh
#   ORDER_BY=volume ./raydium_ammv3_pools.sh

# Ativar modo de depuração opcional (DEBUG=true)
if [ "${DEBUG}" = "true" ]; then
    set -x
fi

# Verifica se as dependências estão instaladas
command -v curl >/dev/null 2>&1 || { echo "Este script requer curl. Instale-o primeiro."; exit 1; }
command -v jq   >/dev/null 2>&1 || { echo "Este script requer jq. Instale-o primeiro.";   exit 1; }

# API endpoints
API_POOLS="https://api.raydium.io/v2/ammV3/ammPools"
API_TOKENS="https://api.raydium.io/v2/sdk/tokenList"

# Criar arquivos temporários
TEMP_POOLS="$(mktemp /tmp/raydium_ammv3_pools.XXXXXX)"
TEMP_TOKENS="$(mktemp /tmp/raydium_ammv3_tokens.XXXXXX)"
trap 'rm -f "$TEMP_POOLS" "$TEMP_TOKENS"' EXIT

# Parâmetro de ordenação (padrão: Fee 24h)
ORDER_BY=${ORDER_BY:-fee}
ORDER_COLUMN=5
case "$ORDER_BY" in
    liquidez) ORDER_COLUMN=2 ;;
    volume)   ORDER_COLUMN=3 ;;
    apr)      ORDER_COLUMN=4 ;;
    apr1d)    ORDER_COLUMN=6 ;;
    fee)      ORDER_COLUMN=5 ;;
    *) echo "Ordenação inválida: $ORDER_BY. Opções: liquidez, volume, apr, apr1d, fee"; exit 1 ;;
esac

# Função de log para depuração
log_debug() { echo "[DEBUG] $1" >&2; }

# Baixar dados dos pools
log_debug "Buscando dados da API em: $API_POOLS"
if ! curl -s --fail --show-error -o "$TEMP_POOLS" "$API_POOLS"; then
    log_debug "Erro ao buscar dados da API."
    exit 1
fi

# Baixar lista de tokens para obter nomes reais dos tokens
log_debug "Buscando lista de tokens da API em: $API_TOKENS"
if ! curl -s --fail --show-error -o "$TEMP_TOKENS" "$API_TOKENS"; then
    log_debug "Erro ao buscar tokens da API."
    exit 1
fi

# Verifica se os dados de pools foram retornados corretamente
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

# Cabeçalho
echo "-----------------------------------------------------------------------------------------------------------------------------"
echo " Pool Name         | Liquidez (USD) | Volume 24h (USD) | APR 24h (%) | APR 1d (%) | Fee 24h (USD) | Pool ID"
echo "-----------------------------------------------------------------------------------------------------------------------------"

# Função para buscar nome dos tokens
get_token_name() {
    local mint="$1"
    jq -r --arg mint "$mint" '.tokens[] | select(.mint == $mint) | .symbol' "$TEMP_TOKENS" | head -n 1
}

# Processar pools e aplicar filtros
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
          ((.day.apr // 0) * 100) / 365,
          (.day.volumeFee // 0),
          (.id // "N/A") ] |
        join("|")' \
       "$TEMP_POOLS"
)"

# Contador de pools filtrados
POOL_COUNT=0

if [ -z "$FILTERED_POOLS" ]; then
    log_debug "Nenhum pool atende aos critérios de filtro."
    echo "Nenhum pool encontrado com os critérios especificados."
    exit 0
fi

log_debug "Pools filtrados encontrados. Exibindo resultados..."

# Processar pools e exibir formatado
echo "$FILTERED_POOLS" \
    | sort -t'|' -k"$ORDER_COLUMN" -nr \
    | while IFS='|' read -r baseMint quoteMint tvl volume24h apr24h apr1d fee24h pool_id; do
        baseToken=$(get_token_name "$baseMint")
        quoteToken=$(get_token_name "$quoteMint")
        pool_name="${baseToken}/${quoteToken}"

        # Formatar números
        tvl_formatted="$(LC_NUMERIC=en_US.UTF-8 printf "%'d" "$tvl" 2>/dev/null || printf "%d" "$tvl")"
        volume24h_formatted="$(LC_NUMERIC=en_US.UTF-8 printf "%'d" "$volume24h" 2>/dev/null || printf "%d" "$volume24h")"
        fee24h_formatted="$(LC_NUMERIC=en_US.UTF-8 printf "%'d" "$fee24h" 2>/dev/null || printf "%d" "$fee24h")"
        apr24h_formatted="$(printf "%.2f" "$apr24h")"
        apr1d_formatted="$(printf "%.2f" "$apr1d")"

        printf "%-20s | %15s | %15s | %10s | %10s | %15s | %-40s\n" \
               "$pool_name" \
               "$tvl_formatted" \
               "$volume24h_formatted" \
               "$apr24h_formatted" \
               "$apr1d_formatted" \
               "$fee24h_formatted" \
               "$pool_id"

        ((POOL_COUNT++))
    done

echo "-----------------------------------------------------------------------------------------------------------------------------"
echo "Total de pools exibidos: $POOL_COUNT"
log_debug "Script concluído em $(date)"
