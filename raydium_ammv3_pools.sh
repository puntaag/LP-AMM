#!/usr/bin/env bash

# Definição da API correta
API_POOLS="https://api-v3.raydium.io/pools/info/list"

# Criar arquivos temporários
TEMP_POOLS="$(mktemp /tmp/raydium_v3_pools.XXXXXX)"
# trap 'rm -f "$TEMP_POOLS"' EXIT  # Desativar remoção automática para debug

# Função de log de depuração
log_debug() {
    echo "[DEBUG] $1" >&2
}

# Solicitar a ordem de exibição
echo "Escolha o critério de ordenação:"
echo "1 - Liquidez"
echo "2 - Volume 24h (USD)"
echo "3 - Fee 24h (Taxa arrecadada)"
echo "4 - APR 24h (%)"
echo "5 - Volume 7d (USD)"
echo "6 - Fee 7d (Taxa arrecadada)"
echo "7 - APR 7d (%)"
echo "8 - Volume 30d (USD)"
echo "9 - Fee 30d (Taxa arrecadada)"
echo "10 - APR 30d (%)"
read -p "Digite a opção desejada (1-10): " ORDER_OPTION

# Definir o campo de ordenação com base na escolha do usuário
case "$ORDER_OPTION" in
    1) ORDER_BY="liquidity" ;;
    2) ORDER_BY="volume24h" ;;
    3) ORDER_BY="fee24h" ;;
    4) ORDER_BY="apr24h" ;;
    5) ORDER_BY="volume7d" ;;
    6) ORDER_BY="fee7d" ;;
    7) ORDER_BY="apr7d" ;;
    8) ORDER_BY="volume30d" ;;
    9) ORDER_BY="fee30d" ;;
    10) ORDER_BY="apr30d" ;;
    *) 
       echo "Opção inválida! Usando 'liquidity' como padrão."
       ORDER_BY="liquidity"
    ;;
esac

SORT_TYPE="desc"

# Loop para atualização contínua a cada 30 segundos
while true; do
    # Buscar pools da API v3
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

    # Processamento dos dados e exibição formatada
    echo "------------------------------------------------------------------------------------------------------------------------------------"
    echo " Pool ID                             | Liquidez (USD) | Volume 24h (USD) | Volume Última Hora (USD) | APR 1d (%) | APR 7d (%) | Token A | Token B"
    echo "------------------------------------------------------------------------------------------------------------------------------------"

    FILTERED_POOLS="$(
        jq -r '
            .data.data | map([
                (.id // "N/A"),
                (.liquidity // 0) | tostring,
                (.volume24h // 0) | tostring,
                (.apr24h // 0) | tostring,
                (.apr7d // 0) | tostring,
                (.mintA.symbol // "N/A"),
                (.mintB.symbol // "N/A")
            ] | join("|")) | .[]
        ' "$TEMP_POOLS"
    )"

    if [ -n "$FILTERED_POOLS" ]; then
        echo "$FILTERED_POOLS" | while IFS='|' read -r pool_id liquidity volume apr1d apr7d token_a token_b; do
            # Garantir que valores vazios sejam convertidos para zero
            liquidity=$(echo "$liquidity" | awk '{ if ($0 == "") print "0"; else print $0 }')
            volume=$(echo "$volume" | awk '{ if ($0 == "") print "0"; else print $0 }')
            apr1d=$(echo "$apr1d" | awk '{ if ($0 == "") print "0"; else print $0 }')
            apr7d=$(echo "$apr7d" | awk '{ if ($0 == "") print "0"; else print $0 }')

            # Calcular Volume da Última Hora
            volume_1h=$(awk "BEGIN {print $volume / 24}")

            # Formatar corretamente os números para evitar erro de printf
            printf "%-35s | %15.2f | %15.2f | %20.2f | %10.2f | %10.2f | %7s | %7s\n" \
                   "$pool_id" "$liquidity" "$volume" "$volume_1h" "$apr1d" "$apr7d" "$token_a" "$token_b"
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
