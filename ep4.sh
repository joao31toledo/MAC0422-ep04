#!/bin/bash

# --- Configurações Comuns ---
PORTA_INET="1500" # Porta usada pelos servidores Inet
UNIX_SOCKET_PATH="/tmp/uds-echo.sock" # Caminho do socket Unix

echo "--- Iniciando o Script de Teste EP4 ---"

# --- Parte 1: Compilação de todos os códigos ---
echo "Compilando todos os executáveis..."

# Servidores
declare -A SERVIDORES_EXEC
SERVIDORES_EXEC["ep4-servidor-inet_processos"]="gcc ep4-clientes+servidores/ep4-servidor-inet_processos.c -o /tmp/ep4-servidor-inet_processos -Wall"
SERVIDORES_EXEC["ep4-servidor-inet_threads"]="gcc ep4-clientes+servidores/ep4-servidor-inet_threads.c -o /tmp/ep4-servidor-inet_threads -Wall -pthread"
SERVIDORES_EXEC["ep4-servidor-inet_muxes"]="gcc ep4-clientes+servidores/ep4-servidor-inet_muxes.c -o /tmp/ep4-servidor-inet_muxes -Wall"
SERVIDORES_EXEC["ep4-servidor-unix_threads"]="gcc ep4-clientes+servidores/ep4-servidor-unix_threads.c -o /tmp/ep4-servidor-unix_threads -Wall -pthread"

# Clientes
CLIENTES_COMPILACAO=(
    "ep4-cliente-inet.c:/tmp/ep4-cliente-inet"
    "ep4-cliente-unix.c:/tmp/ep4-cliente-unix"
)

# Compilar servidores
for nome_servidor in "${!SERVIDORES_EXEC[@]}"; do
    comando_compilacao="${SERVIDORES_EXEC[$nome_servidor]}"
    echo "  Compilando $nome_servidor..."
    $comando_compilacao
    if [ ! -f "/tmp/$nome_servidor" ]; then
        echo "!!! ERRO: Falha na compilação de $nome_servidor. Abortando."
        exit 1
    fi
done

# Compilar clientes
for cliente_info in "${CLIENTES_COMPILACAO[@]}"; do
    source_file=$(echo "$cliente_info" | cut -d':' -f1) # e.g., ep4-cliente-inet.c
    output_path=$(echo "$cliente_info" | cut -d':' -f2) # e.g., /tmp/ep4-cliente-inet
    nome_cliente=$(basename "$output_path") # e.g., ep4-cliente-inet

    echo "  Compilando $nome_cliente..."
    gcc "ep4-clientes+servidores/$source_file" -o "$output_path" -Wall

    if [ ! -f "$output_path" ]; then
        echo "!!! ERRO: Falha na compilação de $nome_cliente. Abortando."
        exit 1
    fi
done

echo "Todos os executáveis compilados com sucesso."

# --- Parte 2: Geração de Arquivos ---
num_clientes=$1
shift # Remove o primeiro argumento (num_clientes) da lista

if [ -z "$num_clientes" ] || [ "$#" -eq 0 ]; then
    echo "Uso: $0 <num_clientes_simultaneos> <tamanho_arquivo_MB_1> [tamanho_arquivo_MB_2]..."
    echo "Exemplo: $0 1 5 10"
    exit 1
fi

echo ">>>>>>> Gerando arquivos de teste..."
ARQUIVOS_TESTE=() # Array para armazenar os caminhos dos arquivos gerados

for tamanho_mb in "$@"; do
    tamanho_bytes=$((tamanho_mb * 1024 * 1024))
    nome_arquivo_base=$(printf "%02dMB" "$tamanho_mb")
    caminho_arquivo="/tmp/arquivo_${nome_arquivo_base}.txt"

    echo "  Gerando arquivo de ${tamanho_mb}MB: ${caminho_arquivo}"
    base64 /dev/urandom | head -c ${tamanho_bytes} > "${caminho_arquivo}"
    echo >> "${caminho_arquivo}" # Adiciona uma nova linha no final do arquivo
    
    if [ -f "$caminho_arquivo" ] && [ "$(stat -c%s "$caminho_arquivo")" -ge "$tamanho_bytes" ]; then
        echo "  Arquivo ${caminho_arquivo} gerado com sucesso."
        ARQUIVOS_TESTE+=("$caminho_arquivo") # Adiciona ao array de arquivos
    else
        echo "!!! ERRO: Falha ao gerar o arquivo ${caminho_arquivo}."
        exit 1
    fi
done

echo "Todos os arquivos de teste gerados: ${ARQUIVOS_TESTE[@]}"

# --- Parte 3: Teste de Inicialização e Encerramento de Servidores ---

for servidor_executavel_path in "${!SERVIDORES_EXEC[@]}"; do
    nome_servidor="$servidor_executavel_path" # e.g., ep4-servidor-inet_processos
    caminho_executavel="/tmp/$nome_servidor" # e.g., /tmp/ep4-servidor-inet_processos

    echo -e "\n--- Testando o Servidor: $nome_servidor ---"

    # Garantir que nenhuma execução anterior do servidor esteja em funcionamento
    pids_existentes=$(pgrep -f "$nome_servidor")
    if [ -n "$pids_existentes" ]; then
        echo "  --> Encontrado(s) PID(s) anterior(es) para $nome_servidor: $pids_existentes. Matando-o(s)..."
        sudo kill -9 $pids_existentes
        sleep 3 # Dê um tempo para o sistema processar a morte
        if pgrep -f "$nome_servidor" > /dev/null; then
            echo "  !!! ERRO: Processo $nome_servidor (PID(s) $pids_existentes) não terminou após kill -9. Abortando."
            exit 1
        else
            echo "  Instâncias anteriores de $nome_servidor encerradas."
        fi
    else
        echo "  Nenhuma instância anterior de $nome_servidor encontrada."
    fi

    # Para sockets Unix: garantir que o arquivo de socket não exista
    if [[ "$nome_servidor" == "ep4-servidor-unix_threads" ]]; then
        if [ -e "$UNIX_SOCKET_PATH" ]; then
            echo "  --> Removendo arquivo de socket Unix antigo: $UNIX_SOCKET_PATH"
            rm -f "$UNIX_SOCKET_PATH"
        fi
    fi

    # Iniciar o servidor em segundo plano
    echo "Subindo o servidor $nome_servidor..."
    "$caminho_executavel" &
    SERVER_PID_PAI=$! # Captura o PID do processo PAI

    # Variável para armazenar o PID real do daemon/processo principal
    server_pid="" 

    # --- Lógica de Verificação de Inicialização ---
    if [[ "$nome_servidor" =~ ^ep4-servidor-inet_ ]]; then # Para TODOS os servidores inet (processos, threads, muxes)
        echo "  Verificando se $nome_servidor está ouvindo na porta $PORTA_INET..."
        SERVER_UP=false
        SERVER_PID_DAEMON=""

        for i in $(seq 1 15); do # Aumentei o timeout para 15s para ser mais seguro
            if sudo lsof -i :$PORTA_INET | grep -q "ep4-servi"; then
                SERVER_UP=true
                SERVER_PID_DAEMON=$(sudo lsof -t -i :$PORTA_INET 2>/dev/null | head -n 1)
                break
            fi
            sleep 1
        done

        if [ "$SERVER_UP" = true ]; then
            if [ -n "$SERVER_PID_DAEMON" ] && ps -p "$SERVER_PID_DAEMON" > /dev/null; then
                echo "  Servidor $nome_servidor subiu e está ouvindo na porta $PORTA_INET com PID: $SERVER_PID_DAEMON"
                server_pid="$SERVER_PID_DAEMON"
            else
                echo "  !!! ERRO: Servidor $nome_servidor subiu, mas não conseguimos encontrar o PID ativo (`$SERVER_PID_DAEMON`). Verifique manualmente."
                exit 1
            fi
        else
            echo "  !!! ERRO: Servidor $nome_servidor não subiu e não está ouvindo na porta $PORTA_INET em 15s. Falha na inicialização."
            exit 1
        fi
    elif [[ "$nome_servidor" == "ep4-servidor-unix_threads" ]]; then
        echo "  Verificando se $nome_servidor criou o socket Unix em $UNIX_SOCKET_PATH (daemonizado)..."
        SERVER_UP=false
        SERVER_PID_DAEMON=""

        for i in $(seq 1 15); do # Aumentei o timeout para 15s aqui também
            if [ -e "$UNIX_SOCKET_PATH" ] && pgrep -f "$nome_servidor" > /dev/null; then
                SERVER_UP=true
                SERVER_PID_DAEMON=$(pgrep -f "$nome_servidor" | head -n 1)
                break
            fi
            sleep 1
        done

        if [ "$SERVER_UP" = true ]; then
            if [ -n "$SERVER_PID_DAEMON" ] && ps -p "$SERVER_PID_DAEMON" > /dev/null; then
                echo "  Servidor $nome_servidor subiu e criou o socket Unix com PID: $SERVER_PID_DAEMON"
                server_pid="$SERVER_PID_DAEMON"
            else
                echo "  !!! ERRO: Servidor $nome_servidor criou o socket, mas não conseguimos encontrar o PID ativo (`$SERVER_PID_DAEMON`). Verifique manualmente."
                exit 1
            fi
        else
            echo "  !!! ERRO: Servidor $nome_servidor não subiu e não criou o socket Unix em $UNIX_SOCKET_PATH em 15s. Falha na inicialização."
            exit 1
        fi
    else
        # Fallback para outros tipos de servidor não especificados (menos provável agora)
        sleep 2
        if ps -p "$SERVER_PID_PAI" > /dev/null; then
            echo "  Servidor $nome_servidor subiu com PID: $SERVER_PID_PAI"
            server_pid="$SERVER_PID_PAI"
        else
            echo "  !!! ERRO: Servidor $nome_servidor falhou ao iniciar. Verifique os logs do journalctl."
            journalctl -q -n 20 _PID=$SERVER_PID_PAI --since "today"
            exit 1
        fi
    fi

    # --- Parte de teste de clientes concorrentes com arquivos ---
    echo "  Iniciando teste de echo com arquivos de diferentes tamanhos e $num_clientes clientes concorrentes..."
    
    CLIENT_SUCCESS_GLOBAL=true # Flag para o sucesso geral dos testes

    # Loop para cada arquivo de teste gerado
    for arquivo_teste in "${ARQUIVOS_TESTE[@]}"; do
        tamanho_mb=$(basename "$arquivo_teste" | sed 's/arquivo_\([0-9]\+\)MB\.txt/\1/')
        echo "    Testando com arquivo de ${tamanho_mb}MB..."

        CLIENT_EXEC=""
        CLIENT_ARGS=""
        if [[ "$nome_servidor" =~ ^ep4-servidor-inet_ ]]; then
            CLIENT_EXEC="/tmp/ep4-cliente-inet"
            CLIENT_ARGS="127.0.0.1" # Apenas IP, porta hardcoded no cliente C
            echo "      Usando $CLIENT_EXEC para conectar a 127.0.0.1 (porta hardcoded no cliente C)"
        elif [[ "$nome_servidor" == "ep4-servidor-unix_threads" ]]; then
            CLIENT_EXEC="/tmp/ep4-cliente-unix"
            CLIENT_ARGS="$UNIX_SOCKET_PATH"
            echo "      Usando $CLIENT_EXEC para conectar a $UNIX_SOCKET_PATH"
        else
            echo "      Aviso: Cliente não definido para o servidor $nome_servidor. Pulando teste."
            continue # Pula para o próximo arquivo se o cliente não for definido
        fi

        # Se o cliente executável não existe, pula
        if [ ! -f "$CLIENT_EXEC" ]; then
            echo "      !!! ERRO: Executável do cliente $CLIENT_EXEC não encontrado. Pulando teste."
            CLIENT_SUCCESS_GLOBAL=false
            continue
        fi

        PIDS_AND_FILES=() # Array para armazenar PID, e nomes de arquivos de saída/erro para cada cliente
        
        START_TIME=$(date +%s.%N) # Captura o tempo de início em nanossegundos

        # Loop para lançar múltiplos clientes em segundo plano
        for ((i=0; i<num_clientes; i++)); do
            temp_output_file=$(mktemp /tmp/${nome_servidor}_client_output_"$i"_XXXXXX.txt)
            temp_error_file=$(mktemp /tmp/${nome_servidor}_client_error_"$i"_XXXXXX.txt)
            
            cat "$arquivo_teste" | "$CLIENT_EXEC" $CLIENT_ARGS > "$temp_output_file" 2> "$temp_error_file" &
            PIDS_AND_FILES+=("$!" "$temp_output_file" "$temp_error_file") # Adiciona PID e arquivos ao array
        done

        # Espera que todos os clientes concorrentes terminem e verifica suas saídas
        ALL_CLIENTS_GOT_RESPONSE=true # Nova flag para verificar se cada cliente recebeu ALGUMA resposta
        CLIENT_ERRORS_FOUND=false

        for ((idx=0; idx<${#PIDS_AND_FILES[@]}; idx+=3)); do
            pid="${PIDS_AND_FILES[idx]}"
            output_file="${PIDS_AND_FILES[idx+1]}"
            error_file="${PIDS_AND_FILES[idx+2]}"

            wait "$pid"
            EXIT_STATUS=$? # Captura o status de saída do cliente

            OUTPUT_CONTENT=$(cat "$output_file")
            ERROR_CONTENT=$(cat "$error_file")

            # Verifica se houve alguma resposta (para arquivos grandes, não comparamos o conteúdo)
            if [ -z "$OUTPUT_CONTENT" ]; then # Se a saída está vazia, o cliente não recebeu echo
                echo "      !!! FALHA do Cliente PID $pid: NENHUMA resposta recebida para arquivo de ${tamanho_mb}MB."
                ALL_CLIENTS_GOT_RESPONSE=false
            fi

            # Verifica se houve erro (ignorando o "fgets" conhecido)
            if [ "$EXIT_STATUS" -ne 0 ] && [[ ! "$ERROR_CONTENT" =~ "Erro no fgets... ou o arquivo chegou no fim" ]]; then
                echo "      !!! ERRO CRÍTICO do Cliente PID $pid: Código de saída $EXIT_STATUS. Erro: '$ERROR_CONTENT'"
                CLIENT_ERRORS_FOUND=true
            elif [ -n "$ERROR_CONTENT" ]; then # Se há qualquer erro, mas é o esperado do fgets
                echo "      Aviso do Cliente PID $pid (erro esperado): '$ERROR_CONTENT'"
            fi
            
            # Limpa os arquivos temporários
            rm "$output_file" "$error_file"
        done

        END_TIME=$(date +%s.%N) # Captura o tempo de fim em nanossegundos
        ELAPSED_TIME=$(echo "$END_TIME - $START_TIME" | bc) # Calcula o tempo decorrido

        echo "    Tempo total para ${num_clientes} clientes concorrentes (arquivo ${tamanho_mb}MB): ${ELAPSED_TIME} segundos."

        if [ "$ALL_CLIENTS_GOT_RESPONSE" = true ] && [ "$CLIENT_ERRORS_FOUND" = false ]; then
            echo "  Todos os ${num_clientes} clientes concorrentes para ${tamanho_mb}MB concluíram e receberam uma resposta (ignorando erros esperados de fgets)."
        else
            echo "!!! ERRO: Um ou mais clientes falharam ou não receberam resposta para ${tamanho_mb}MB. Abortando."
            CLIENT_SUCCESS_GLOBAL=false # Marca falha geral
        fi
    done # Fim do loop de arquivos

    if [ "$CLIENT_SUCCESS_GLOBAL" = false ]; then
        exit 1
    fi

    # --- Encerramento do Servidor ---
    echo "Enviando sinal 15 para encerrar o servidor $nome_servidor (PID ${server_pid:-N/A})..." # Handle N/A if PID not found
    if [ -n "$server_pid" ]; then
        sudo kill -15 "$server_pid"
        sleep 2 # Dá um tempo para o servidor encerrar graciosamente

        # Verificar se o servidor realmente encerrou
        if ps -p "$server_pid" > /dev/null; then
            echo "  !!! AVISO: Servidor $nome_servidor (PID $server_pid) não encerrou com sinal 15. Forçando encerramento com sinal 9."
            sudo kill -9 "$server_pid"
            sleep 3
            if ps -p "$server_pid" > /dev/null; then
                echo "  !!! ERRO CRÍTICO: Servidor $nome_servidor (PID $server_pid) ainda rodando após kill -9. Abortando."
                exit 1
            else
                echo "  Servidor $nome_servidor (PID $server_pid) encerrado à força."
            fi
        else
            echo "  Servidor $nome_servidor (PID $server_pid) encerrado com sucesso."
        fi
    else
        echo "  Não foi possível encontrar o PID do servidor $nome_servidor para encerrar. Verifique manualmente."
    fi

    echo "Pausa de 2 segundos antes do próximo servidor..."
    sleep 2

done

echo -e "\n--- Testes de Inicialização de Servidores Concluídos ---"