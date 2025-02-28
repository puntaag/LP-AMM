#!/usr/bin/env bash

# Script para listar pools de liquidez da Raydium (AMM V3) com dados detalhados.

# Ativar modo de depuração opcional
if [ "${DEBUG}" = "true" ]; then
    set -x
fi

# Verifica se as dependências estão instaladas
command -v curl >/dev/null 2>&1 || { echo "Este script requer curl. Instale-o primeiro."; exit 1; }
command -v jq   >/dev/null 2>&1 || { echo "Este script requer jq. Instale-o primeiro.";   exit 1; }

# API endpoint para pools AMM V3
API_URL="https://api.raydium.io/v2/ammV3/ammPools"

# Criar arquivo temporário de forma segura e garantir que seja removido no final
TEMP_FILE="$(mktemp /tmp/raydium_ammv3_pools.XXXXXX)"
trap 'rm -f "$TEMP_FILE"' EXIT

# Função para log de depuração
log_debug() {
    echo "[DEBUG] $1" >&2
}

# Função para formatar números (truncando decimais e inserindo separador de milhar)
format_number() {
    local num="${1%.*}"   # Trunca possíveis decimais
    LC_NUMERIC=en_US.UTF-8 printf "%'d" "$num" 2>/dev/null || printf "%d" "$num"
}

# Verifica se foi passado um parâmetro de ordenação
SORT_FIELD="fee"
if [[ $1 =~ ^sort=(liquidez|volume|apr|fee)$ ]]; then
    SORT_FIELD="${1#sort=}"
fi
log_debug "Ordenando por: $SORT_FIELD"

# Define a chave correta para `sort`
case "$SORT_FIELD" in
    liquidez) SORT_KEY=2 ;;
    volume)   SORT_KEY=3 ;;
    apr)      SORT_KEY=4 ;;
    fee)      SORT_KEY=5 ;;  # Padrão
    *)        SORT_KEY=5 ;;  # Fallback de segurança
esac

log_debug "Buscando dados da API em: $API_URL"
if ! curl -s --fail --show-error -o "$TEMP_FILE" "$API_URL"; then
    log_debug "Erro ao buscar dados da API (curl retornou código $? )."
    exit 1
fi

# Verifica se o arquivo está vazio ou não contém dados válidos
if [ ! -s "$TEMP_FILE" ]; then
    log_debug "Arquivo temporário está vazio ou não foi criado corretamente."
    exit 1
fi

# Verifica se a resposta contém dados válidos
DATA_COUNT="$(jq '.data | length' "$TEMP_FILE" 2>/dev/null)"
if [ -z "$DATA_COUNT" ] || [ "$DATA_COUNT" -eq 0 ]; then
    log_debug "Nenhum dado encontrado na resposta da API. Resposta bruta:"
    cat "$TEMP_FILE"
    exit 1
fi

log_debug "Total de pools encontrados na API: $DATA_COUNT"

# Parâmetros de filtro
MIN_LIQUIDITY=100000
MIN_VOLUME_24H=1000000
MIN_APR_24H=600
LC_NUMERIC=C MIN_APR_DECIMAL="$(awk "BEGIN {print $MIN_APR_24H / 100}")"

log_debug "Filtrando pools com Liquidez >= USD $MIN_LIQUIDITY, Volume 24h >= USD $MIN_VOLUME_24H e APR 24h >= $MIN_APR_24H%..."

echo "--------------------------------------------------------------------------------------------------------------"
echo " Pool Name          | Liquidez (USD) | Volume 24h (USD) | APR 24h (%) | Fee 24h (USD) | Pool ID"
echo "--------------------------------------------------------------------------------------------------------------"

FILTERED_POOLS="$(
    jq -r --argjson min_liq "$MIN_LIQUIDITY" \
    --argjson min_vol "$MIN_VOLUME_24H" \
    --argjson min_apr "$MIN_APR_DECIMAL" \
    '.data[] |
    select(
        (.tvl // 0) >= $min_liq and
        (.day.volume // 0) >= $min_vol and
        (.day.apr // 0) >= $min_apr
    ) |
    {
        name: (if .marketName and .marketName != "" then .marketName 
               elif .name and .name != "" then .name 
               else .lpMint end),
        liquidity: (.tvl // 0),
        volume: (.day.volume // 0),
        apr: ((.day.apr // 0) * 100),
        fee: (.day.volumeFee // 0),
        id: (.id // "N/A")
    } |
    [ .name, .liquidity, .volume, .apr, .fee, .id ] |
    join("|")' "$TEMP_FILE"
)"

if [ -z "$FILTERED_POOLS" ]; then
    log_debug "Nenhum pool atende aos critérios de filtro."
    echo "Nenhum pool encontrado com os critérios especificados."
    exit 0
fi

log_debug "Pools filtrados encontrados. Exibindo resultados..."

echo "$FILTERED_POOLS" | sort -t'|' -k"$SORT_KEY","$SORT_KEY"nr | while IFS='|' read -r name tvl volume24h apr24h fee24h pool_id; do
    tvl_formatted="$(format_number "$tvl")"
    volume24h_formatted="$(format_number "$volume24h")"
    fee24h_formatted="$(format_number "$fee24h")"
    apr24h_formatted="$(printf "%.2f" "$apr24h")"

    printf "%-20s | %15s | %15s | %10s | %15s | %-40s\n" \
           "$name" \
           "$tvl_formatted" \
           "$volume24h_formatted" \
           "$apr24h_formatted" \
           "$fee24h_formatted" \
           "$pool_id"
done

echo "--------------------------------------------------------------------------------------------------------------"
log_debug "Script concluído em $(date)"
