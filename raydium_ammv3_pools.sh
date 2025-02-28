#!/usr/bin/env bash

# Definição das APIs
API_POOLS="https://api-v3.raydium.io/pools/info/list"

# Criar arquivos temporários
TEMP_POOLS="$(mktemp /tmp/raydium_v3_pools.XXXXXX)"
trap 'rm -f "$TEMP_POOLS"' EXIT

# Função de log de depuração
log_debug() {
    echo "[DEBUG] $1" >&2
}

# Definição do campo de ordenação
ORDER_BY="${ORDER_BY:-tvl}"  
SORT_TYPE="desc"

# 🔍 Validação do ORDER_BY
VALID_SORT_FIELDS=("tvl" "day.volume" "day.apr" "week.volume" "week.apr" "month.volume" "month.apr")
if [[ ! " ${VALID_SORT_FIELDS[@]} " =~ " ${ORDER_BY} " ]]; then
    log_debug "Parâmetro ORDER_BY inválido: ${ORDER_BY}. Usando 'tvl' como padrão."
    ORDER_BY="tvl"
fi

# Buscar pools da API v3
log_debug "Buscando pools da API v3 ordenados por $ORDER_BY ($SORT_TYPE)"
if ! curl -s --fail --show-error -o "$TEMP_POOLS" "$API_POOLS?poolType=all&poolSortField=$ORDER_BY&sortType=$SORT_TYPE&pageSize=50&page=1"; then
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
POOL_COUNT=$(jq '.data.data | length' "$TEMP_POOLS" 2>/dev/null || echo 0)
if [[ "$POOL_COUNT" -eq 0 ]]; then
    log_debug "Nenhum pool encontrado na API."
    exit 1
fi
log_debug "Total de pools encontrados na API: $POOL_COUNT"

# **🔍 Ajuste para acessar os campos corretamente**
FILTERED_POOLS="$(
    jq -r --argjson min_tvl 100000 \
          --argjson min_vol 1000000 \
          --argjson min_apr 600 \
    '.data.data | map(
        select(
            (.tvl // 0) >= $min_tvl and
            (.day.volume // 0) >= $min_vol and
            (.day.apr // 0) >= $min_apr
        )
    ) | map([
        (.id // "N/A"),
        (.tvl // 0),
        (.day.volume // 0),
        (.day.apr // 0), 
        (.week.apr // 0),
        (.mintA.symbol // "N/A"),
        (.mintB.symbol // "N/A")
    ] | join("|")) | .[]' "$TEMP_POOLS"
)"

# 🔍 Contagem de pools filtrados
TOTAL_FILTERED=$(echo "$FILTERED_POOLS" | wc -l)
log_debug "Total de pools filtrados: $TOTAL_FILTERED"

# Exibir resultados formatados
echo "---------------------------------------------------------------------------------------------------------------"
echo " Pool ID                             | Liquidez (USD) | Volume 24h (USD) | APR 1d (%) | APR 7d (%) | Token A | Token B"
echo "---------------------------------------------------------------------------------------------------------------"

if [ -n "$FILTERED_POOLS" ]; then
    echo "$FILTERED_POOLS" | while IFS='|' read -r pool_id tvl volume apr1d apr7d token_a token_b; do
        printf "%-35s | %15s | %15s | %10s | %10s | %7s | %7s\n" \
               "$pool_id" "$tvl" "$volume" "$apr1d" "$apr7d" "$token_a" "$token_b"
    done
else
    echo "Nenhum pool encontrado com os critérios especificados."
fi

echo "---------------------------------------------------------------------------------------------------------------"
echo "Total de pools filtrados: $TOTAL_FILTERED"
log_debug "Script concluído em $(date)"
