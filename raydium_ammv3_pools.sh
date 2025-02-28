#!/usr/bin/env bash

# Definição das APIs
API_POOLS="https://api-v3.raydium.io/pools/info/list"
API_TOKENS="https://api-v3.raydium.io/mint/list"

# Criar arquivos temporários
TEMP_POOLS="$(mktemp /tmp/raydium_v3_pools.XXXXXX)"
TEMP_TOKENS="$(mktemp /tmp/raydium_v3_tokens.XXXXXX)"
trap 'rm -f "$TEMP_POOLS" "$TEMP_TOKENS"' EXIT

# Função de log de depuração
log_debug() {
    echo "[DEBUG] $1" >&2
}

# Definição do campo de ordenação
ORDER_BY="${ORDER_BY:-fee24h}"  
SORT_TYPE="desc"

# 🔍 Validação do ORDER_BY
VALID_SORT_FIELDS=("liquidity" "volume24h" "fee24h" "apr24h" "volume7d" "fee7d" "apr7d" "volume30d" "fee30d" "apr30d")
if [[ ! " ${VALID_SORT_FIELDS[@]} " =~ " ${ORDER_BY} " ]]; then
    log_debug "Parâmetro ORDER_BY inválido: ${ORDER_BY}. Usando 'fee24h' como padrão."
    ORDER_BY="fee24h"
fi

# Buscar lista de tokens
log_debug "Buscando lista de tokens da API v3 em: $API_TOKENS"
if ! curl -s --fail --show-error -o "$TEMP_TOKENS" "$API_TOKENS"; then
    log_debug "Erro ao buscar tokens da API v3."
    exit 1
fi
log_debug "Lista de tokens carregada com sucesso."

# Buscar pools da API v3
log_debug "Buscando pools da API v3 ordenados por $ORDER_BY ($SORT_TYPE)"
if ! curl -s --fail --show-error -o "$TEMP_POOLS" "$API_POOLS?poolType=all&poolSortField=$ORDER_BY&sortType=$SORT_TYPE&pageSize=1000&page=1"; then
    log_debug "Erro ao buscar pools da API v3."
    exit 1
fi
log_debug "Pools carregados com sucesso."

# 🔍 Verificação da estrutura do JSON
if ! jq -e . "$TEMP_POOLS" >/dev/null 2>&1; then
    log_debug "Erro: A resposta da API de pools não é um JSON válido."
    cat "$TEMP_POOLS"
    exit 1
fi

# 🔍 Ajuste para acessar os dados corretamente
POOL_COUNT=$(jq '.data | length' "$TEMP_POOLS" 2>/dev/null || echo 0)
if [[ "$POOL_COUNT" -eq 0 ]]; then
    log_debug "Nenhum pool encontrado na API."
    exit 1
fi
log_debug "Total de pools encontrados na API: $POOL_COUNT"

# **🔍 Ajuste para acessar os campos corretamente**
FILTERED_POOLS="$(
    jq -r --argjson min_liq 100000 \
          --argjson min_vol 1000000 \
          --argjson min_apr 600 \
    '.data | map(
        select(
            (.liquidity // 0) >= $min_liq and
            (.volume24h // 0) >= $min_vol and
            ((.apr24h // 0) * 100) >= $min_apr
        )
    ) | map([
        (.market // "N/A"),
        (.liquidity // 0),
        (.volume24h // 0),
        ((.apr7d // 0) * 100), 
        ((.apr24h // 0) * 100),
        (.fee24h // 0),
        (.id // "N/A")
    ] | join("|")) | .[]' "$TEMP_POOLS"
)"

# 🔍 Contagem de pools filtrados
TOTAL_FILTERED=$(echo "$FILTERED_POOLS" | wc -l)
log_debug "Total de pools filtrados: $TOTAL_FILTERED"

# Exibir resultados formatados
echo "---------------------------------------------------------------------------------------------------------------------------------"
echo " Pool Name            | Liquidez (USD) | Volume 24h (USD) | APR 7d (%) | APR 1d (%) | Fee 24h (USD) | Pool ID"
echo "---------------------------------------------------------------------------------------------------------------------------------"

if [ -n "$FILTERED_POOLS" ]; then
    echo "$FILTERED_POOLS" | while IFS='|' read -r name liquidity volume apr7d apr1d fee pool_id; do
        printf "%-20s | %15s | %15s | %10s | %10s | %15s | %-40s\n" \
               "$name" "$liquidity" "$volume" "$apr7d" "$apr1d" "$fee" "$pool_id"
    done
else
    echo "Nenhum pool encontrado com os critérios especificados."
fi

echo "---------------------------------------------------------------------------------------------------------------------------------"
echo "Total de pools filtrados: $TOTAL_FILTERED"
log_debug "Script concluído em $(date)"
