#!/usr/bin/env bash

# Definição da API correta
API_POOLS="https://api-v3.raydium.io/pools/info/list"

# Criar arquivos temporários
TEMP_POOLS="$(mktemp /tmp/raydium_v3_pools.XXXXXX)"
trap 'rm -f "$TEMP_POOLS"' EXIT

# Função de log de depuração
log_debug() {
    echo "[DEBUG] $1" >&2
}

# Solicitar a ordem de exibição
echo "Escolha o critério de ordenação:"
echo "1 - TVL (Total Value Locked)"
echo "2 - Volume 24h (USD)"
echo "3 - Volume na última hora (USD)"
echo "4 - APR 1d (%)"
echo "5 - APR 7d (%)"
read -p "Digite o número correspondente à opção desejada: " ORDER_OPTION

# Definir o campo de ordenação com base na escolha do usuário
case "$ORDER_OPTION" in
    1) ORDER_BY="tvl" ;;
    2) ORDER_BY="day.volume" ;;
    3) ORDER_BY="hour.volume" ;;
    4) ORDER_BY="day.apr" ;;
    5) ORDER_BY="week.apr" ;;
    *) 
        echo "Opção inválida! Usando TVL como padrão."
        ORDER_BY="tvl"
        ;;
esac

SORT_TYPE="desc"

# Loop para atualização contínua a cada 30 segundos
while true; do
    clear  # Limpa a tela para exibir a nova tabela

    log_debug "Buscando pools da API ordenados por $ORDER_BY ($SORT_TYPE)"
    
    if ! curl -s --fail --show-error -o "$TEMP_POOLS" "$API_POOLS?poolType=all&poolSortField=$ORDER_BY&sortType=$SORT_TYPE&pageSize=20&page=1"; then
        log_debug "Erro ao buscar pools da API v3."
        exit 1
    fi
    log_debug "Pools carregados com sucesso."

    # Verificação da estrutura do JSON
    if ! jq -e . "$TEMP_POOLS" >/dev/null 2>&1; then
        log_debug "Erro: A resposta da API de pools não é um JSON válido."
        cat "$TEMP_POOLS"
        exit 1
    fi

    # Contagem de pools
    POOL_COUNT=$(jq '.data.data | length' "$TEMP_POOLS" 2>/dev/null || echo 0)
    if [[ "$POOL_COUNT" -eq 0 ]]; then
        log_debug "Nenhum pool encontrado na API."
        exit 1
    fi
    log_debug "Total de pools encontrados na API: $POOL_COUNT"

    # Exibição formatada da tabela
    echo "------------------------------------------------------------------------------------------------------------------------------------"
    echo " Pool ID                             | Liquidez (USD) | TVL (USD)  | Volume na última hora (USD) | Volume 24h (USD) | APR 1d (%) | APR 7d (%) | Token A | Token B"
    echo "------------------------------------------------------------------------------------------------------------------------------------"

    FILTERED_POOLS="$(
        jq -r '
            .data.data | map([
                (.id // "N/A"),
                (.tvl // 0),
                (.hour.volume // 0), 
                (.day.volume // 0),
                (.day.apr // 0), 
                (.week.apr // 0),
                (.mintA.symbol // "N/A"),
                (.mintB.symbol // "N/A")
            ] | join("|")) | .[]
        ' "$TEMP_POOLS"
    )"

    if [ -n "$FILTERED_POOLS" ]; then
        echo "$FILTERED_POOLS" | while IFS='|' read -r pool_id tvl volume_1h volume_24h apr1d apr7d token_a token_b; do
            printf "%-35s | %15.2f | %10.2f | %28.2f | %15.2f | %10.2f | %10.2f | %7s | %7s\n" \
                   "$pool_id" "$(echo "$tvl" | LC_NUMERIC=C awk '{printf "%.2f", $1}')" \
                   "$(echo "$tvl" | LC_NUMERIC=C awk '{printf "%.2f", $1}')" \
                   "$(echo "$volume_1h" | LC_NUMERIC=C awk '{printf "%.2f", $1}')" \
                   "$(echo "$volume_24h" | LC_NUMERIC=C awk '{printf "%.2f", $1}')" \
                   "$(echo "$apr1d" | LC_NUMERIC=C awk '{printf "%.2f", $1}')" \
                   "$(echo "$apr7d" | LC_NUMERIC=C awk '{printf "%.2f", $1}')" \
                   "$token_a" "$token_b"
        done
    else
        echo "Nenhum pool encontrado com os critérios especificados."
    fi

    echo "------------------------------------------------------------------------------------------------------------------------------------"
    echo "Total de pools filtrados: $POOL_COUNT"
    log_debug "Script atualizado em $(date)"
    
    # Aguarde 30 segundos antes de atualizar
    sleep 30
done
