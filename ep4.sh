#!/bin/bash

# --- Configurações Comuns ---
PORTA_INET="1500" # Porta usada pelos servidores Inet
UNIX_SOCKET_PATH="/tmp/uds-echo.sock" # Caminho do socket Unix

# Lista dos servidores na ordem que devem ser testados (conforme PDF)
declare -a SERVIDORES=(
    "ep4-servidor-inet_processos"
    "ep4-servidor-inet_threads"
    "ep4-servidor-inet_muxes"
    "ep4-servidor-unix_threads"
)

# Strings de log para identificação de início e fim de atendimento ao cliente
# Estas strings devem corresponder exatamente às mensagens que seus servidores imprimem no journald
LOG_START_CLIENT_PATTERN="Passou pelo accept :-)"
LOG_END_CLIENT_PATTERN="Cliente do PID [0-9]+ provavelmente enviou um exit|Cliente da TID [0-9]+ provavelmente enviou um exit|Cliente do socket [0-9]+ provavelmente enviou um exit"

# Define o nome do arquivo de dados para o gnuplot
# O nome do arquivo depende do número de clientes ($1)
N_CLIENTS="$1"
DATA_FILE="/tmp/ep4-resultados-${N_CLIENTS}.data"

# Cria ou limpa o arquivo de dados no início da execução
> "$DATA_FILE"

# --- Requisitos iniciais (parsing de argumentos) ---
num_clientes=$1
shift # Remove o primeiro argumento (num_clientes) da lista

if [ -z "$num_clientes" ] || [ "$#" -eq 0 ]; then
    echo "Uso: $0 <num_clientes_simultaneos> <tamanho_arquivo_MB_1> [tamanho_arquivo_MB_2]..."
    echo "Exemplo: $0 10 5 10"
    exit 1
fi

TAMANHOS_ARQUIVO_ARGS="$@" # Guarda a string original de tamanhos para a mensagem final do gráfico

# --- Parte 1: Compilação dos códigos (Conforme o padrão do PDF) ---

echo "Compilando ep4-servidor-inet_processos"
gcc ep4-clientes+servidores/ep4-servidor-inet_processos.c -o /tmp/ep4-servidor-inet_processos -Wall
if [ $? -ne 0 ]; then echo "!!! ERRO: Falha na compilação de ep4-servidor-inet_processos. Abortando." >&2; exit 1; fi

echo "Compilando ep4-servidor-inet_threads"
gcc ep4-clientes+servidores/ep4-servidor-inet_threads.c -o /tmp/ep4-servidor-inet_threads -Wall -pthread
if [ $? -ne 0 ]; then echo "!!! ERRO: Falha na compilação de ep4-servidor-inet_threads. Abortando." >&2; exit 1; fi

echo "Compilando ep4-servidor-inet_muxes"
gcc ep4-clientes+servidores/ep4-servidor-inet_muxes.c -o /tmp/ep4-servidor-inet_muxes -Wall
if [ $? -ne 0 ]; then echo "!!! ERRO: Falha na compilação de ep4-servidor-inet_muxes. Abortando." >&2; exit 1; fi

echo "Compilando ep4-servidor-unix_threads"
gcc ep4-clientes+servidores/ep4-servidor-unix_threads.c -o /tmp/ep4-servidor-unix_threads -Wall -pthread
if [ $? -ne 0 ]; then echo "!!! ERRO: Falha na compilação de ep4-servidor-unix_threads. Abortando." >&2; exit 1; fi

echo "Compilando ep4-cliente-inet"
gcc ep4-clientes+servidores/ep4-cliente-inet.c -o /tmp/ep4-cliente-inet -Wall
if [ $? -ne 0 ]; then echo "!!! ERRO: Falha na compilação de ep4-cliente-inet. Abortando." >&2; exit 1; fi

echo "Compilando ep4-cliente-unix"
gcc ep4-clientes+servidores/ep4-cliente-unix.c -o /tmp/ep4-cliente-unix -Wall
if [ $? -ne 0 ]; then echo "!!! ERRO: Falha na compilação de ep4-cliente-unix. Abortando." >&2; exit 1; fi


# --- Parte 2: Geração dos arquivos que serão ecoados ---
ARQUIVOS_TESTE=() # Array para armazenar os caminhos dos arquivos gerados

# Gerar todos os arquivos uma única vez no início
for tamanho_mb in "$@"; do
    tamanho_bytes=$((tamanho_mb * 1024 * 1024))
    nome_arquivo_base=$(printf "%02dMB" "$tamanho_mb")
    caminho_arquivo="/tmp/arquivo_${nome_arquivo_base}.txt"

    # Geração física do arquivo, a mensagem ">>>>>>> Gerando um arquivo texto de: XMB..." será impressa no loop principal
    base64 /dev/urandom | head -c ${tamanho_bytes} > "${caminho_arquivo}"
    echo >> "${caminho_arquivo}" # Adiciona uma nova linha no final do arquivo (garante que fgets não trave no EOF)
    
    if [ ! -f "$caminho_arquivo" ] || [ "$(stat -c%s "$caminho_arquivo")" -lt "$tamanho_bytes" ]; then
        echo "!!! ERRO: Falha ao gerar o arquivo ${caminho_arquivo}. Abortando." >&2
        exit 1
    fi
    ARQUIVOS_TESTE+=("$caminho_arquivo")
done


# --- Parte 3: Execução dos servidores e clientes concorrentes ---

# Loop externo: itera sobre os tamanhos dos arquivos (conforme requisito 2.2 do PDF)
for arquivo_teste_path in "${ARQUIVOS_TESTE[@]}"; do
    tamanho_mb=$(basename "$arquivo_teste_path" | sed 's/arquivo_\([0-9]\+\)MB\.txt/\1/')
    
    # Mensagem de geração de arquivo (conforme PDF, repetida para cada arquivo)
    echo "" # Linha em branco para melhor espaçamento no terminal
    echo ">>>>>>> Gerando um arquivo texto de: ${tamanho_mb}MB..."

    # --- INÍCIO DO CÓDIGO A ADICIONAR ---
    # Resetar as variáveis de tempo para cada novo tamanho de arquivo
    TIME_INET_PROCESSOS=""
    TIME_INET_THREADS=""
    TIME_INET_MUXES=""
    TIME_UNIX_THREADS=""
    # --- FIM DO CÓDIGO A ADICIONAR ---

    # Loop interno: itera sobre os servidores (conforme requisito 2.3 do PDF)
    for nome_servidor_exec in "${SERVIDORES[@]}"; do
        caminho_executavel="/tmp/$nome_servidor_exec"

        # --- Garantir ambiente limpo e subir servidor ---
        pids_existentes=$(pgrep -f "$nome_servidor_exec")
        if [ -n "$pids_existentes" ]; then
            # Matar instâncias anteriores silenciosamente, não é parte da saída do PDF
            sudo kill -9 $pids_existentes >/dev/null 2>&1
            sleep 1 # Pequena pausa para o processo ser encerrado
        fi

        # Para sockets Unix: garantir que o arquivo de socket não exista
        if [[ "$nome_servidor_exec" == "ep4-servidor-unix_threads" ]]; then
            if [ -e "$UNIX_SOCKET_PATH" ]; then
                rm -f "$UNIX_SOCKET_PATH" >/dev/null 2>&1
            fi
        fi

        # Mensagem de subida do servidor (conforme PDF)
        echo "" # Linha em branco para espaçamento
        echo "Subindo o servidor $nome_servidor_exec"
        
        # Guarda o tempo de início do servidor para o --since do journalctl (requisito 2.6)
        SERVER_START_DATE=$(date +'%Y-%m-%d %H:%M:%S')

        # Iniciar o servidor em segundo plano (redirecionando saída e erro)
        if [[ "$nome_servidor_exec" =~ ^ep4-servidor-inet_ ]]; then
            "$caminho_executavel" $PORTA_INET >/dev/null 2>&1 & # Servidores INET usam a porta configurada
        elif [[ "$nome_servidor_exec" == "ep4-servidor-unix_threads" ]]; then
            "$caminho_executavel" >/dev/null 2>&1 &
        fi
        
        SERVER_PID_PAI=$! # Captura o PID do processo pai

        # --- Lógica de Verificação de Inicialização Robusta ---
        SERVER_UP=false
        SERVER_PID_DAEMON=""

        if [[ "$nome_servidor_exec" =~ ^ep4-servidor-inet_ ]]; then
            # Verifica servidores INET (processos, threads, muxes) pelo lsof na porta
            for i in $(seq 1 15); do # Timeout de 15s para robustez
                if sudo lsof -i :$PORTA_INET | grep -q "ep4-servi"; then
                    SERVER_UP=true
                    SERVER_PID_DAEMON=$(sudo lsof -t -i :$PORTA_INET 2>/dev/null | head -n 1)
                    break
                fi
                sleep 1
            done
        elif [[ "$nome_servidor_exec" == "ep4-servidor-unix_threads" ]]; then
            # Verifica servidor Unix threads pela existência do arquivo de socket e pgrep
            for i in $(seq 1 15); do # Timeout de 15s para robustez
                if [ -e "$UNIX_SOCKET_PATH" ] && pgrep -f "$nome_servidor_exec" > /dev/null; then
                    SERVER_UP=true
                    SERVER_PID_DAEMON=$(pgrep -f "$nome_servidor_exec" | head -n 1)
                    break
                fi
                sleep 1
            done
        fi

        if [ "$SERVER_UP" = true ]; then
            if [ -n "$SERVER_PID_DAEMON" ] && ps -p "$SERVER_PID_DAEMON" > /dev/null; then
                server_pid="$SERVER_PID_DAEMON" # Define o PID real do daemon
                #echo "  (Servidor $nome_servidor_exec subiu com PID: $server_pid)" >&2 # Para depuração, não no PDF
            else
                echo "!!! ERRO: Servidor $nome_servidor_exec subiu, mas não conseguimos encontrar o PID ativo. Abortando." >&2
                sudo kill -9 "$SERVER_PID_PAI" >/dev/null 2>&1 # Tenta matar o processo pai também
                exit 1
            fi
        else
            echo "!!! ERRO: Servidor $nome_servidor_exec não subiu em tempo. Abortando." >&2
            sudo kill -9 "$SERVER_PID_PAI" >/dev/null 2>&1 # Tenta matar o processo pai também
            exit 1
        fi


        # --- Execução dos clientes concorrentes ---
        echo "" # Linha em branco para espaçamento
        echo ">>>>>>> Fazendo ${num_clientes} clientes ecoarem um arquivo de: ${tamanho_mb}MB..."

        CLIENT_EXEC=""
        CLIENT_ARGS=""
        if [[ "$nome_servidor_exec" =~ ^ep4-servidor-inet_ ]]; then
            CLIENT_EXEC="/tmp/ep4-cliente-inet"
            CLIENT_ARGS="127.0.0.1" # IP fixo, porta hardcoded no cliente C
        elif [[ "$nome_servidor_exec" == "ep4-servidor-unix_threads" ]]; then
            CLIENT_EXEC="/tmp/ep4-cliente-unix"
            CLIENT_ARGS="$UNIX_SOCKET_PATH"
        else
            echo "!!! ERRO: Cliente não definido para o servidor $nome_servidor_exec. Abortando." >&2
            sudo kill -15 "$server_pid" >/dev/null 2>&1 # Tenta matar o servidor
            exit 1
        fi

        if [ ! -f "$CLIENT_EXEC" ]; then
            echo "!!! ERRO: Executável do cliente ${CLIENT_EXEC} não encontrado. Abortando." >&2
            sudo kill -15 "$server_pid" >/dev/null 2>&1 # Tenta matar o servidor
            exit 1
        fi

        PIDS_AND_FILES=() # Array para armazenar PID, e nomes de arquivos de saída/erro para cada cliente
        
        # Não captura mais o START_TIME aqui, será do journald

        # Loop para lançar múltiplos clientes em segundo plano
        for ((i=0; i<num_clientes; i++)); do
            temp_output_file=$(mktemp /tmp/${nome_servidor_exec}_client_output_"$i"_XXXXXX.txt)
            temp_error_file=$(mktemp /tmp/${nome_servidor_exec}_client_error_"$i"_XXXXXX.txt)
            
            # Redireciona stdout e stderr para arquivos temporários e roda em background
            cat "$arquivo_teste_path" | "$CLIENT_EXEC" $CLIENT_ARGS > "$temp_output_file" 2> "$temp_error_file" &
            PIDS_AND_FILES+=("$!" "$temp_output_file" "$temp_error_file")
        done

        # --- Aguardando os clientes terminarem ---
        echo "" # Linha em branco para espaçamento
        echo "Esperando os clientes terminarem..." # Conforme PDF

        ALL_CLIENTS_GOT_RESPONSE=true # Flag para verificar se cada cliente recebeu ALGUMA resposta
        CLIENT_CRITICAL_ERRORS_FOUND=false # Flag para erros que não são o "fgets"
        CLIENT_FGETS_WARNINGS_COLLECTED="" # Para coletar mensagens de "fgets"

        for ((idx=0; idx<${#PIDS_AND_FILES[@]}; idx+=3)); do
            pid_cliente="${PIDS_AND_FILES[idx]}"
            output_file="${PIDS_AND_FILES[idx+1]}"
            error_file="${PIDS_AND_FILES[idx+2]}"

            wait "$pid_cliente" # Espera pelo cliente
            EXIT_STATUS=$? # Captura o status de saída

            OUTPUT_CONTENT=$(cat "$output_file")
            ERROR_CONTENT=$(cat "$error_file")

            # Verifica se houve alguma resposta (para arquivos grandes, apenas a presença importa)
            if [ -z "$OUTPUT_CONTENT" ]; then
                ALL_CLIENTS_GOT_RESPONSE=false
            fi

            # Verifica erros do cliente (ignorando o fgets)
            if [ "$EXIT_STATUS" -ne 0 ] && [[ ! "$ERROR_CONTENT" =~ "Erro no fgets... ou o arquivo chegou no fim" ]]; then
                CLIENT_CRITICAL_ERRORS_FOUND=true
            elif [ -n "$ERROR_CONTENT" ]; then
                CLIENT_FGETS_WARNINGS_COLLECTED="${CLIENT_FGETS_WARNINGS_COLLECTED}, Cliente PID ${pid_cliente}: Erro esperado: \"${ERROR_CONTENT}\"\n"
            fi
            
            rm "$output_file" "$error_file" # Remove arquivos temporários
        done

        # --- Contabilização do tempo (Requisito 2.6) ---
        echo "" # Linha em branco para espaçamento
        echo "Verificando os instantes de tempo no journald..." # Conforme PDF

        # Captura todos os logs relevantes do servidor desde o início da sua execução
        # Usamos -o short-iso para um formato de data/hora fácil de parsear pelo dateutils.diff
        SERVER_LOGS=$(sudo journalctl --since="$SERVER_START_DATE" -t "$nome_servidor_exec" -q -o short-iso)
        
        # Extrai o timestamp do primeiro cliente atendido
        # LOG_START_CLIENT_PATTERN é uma string fixa, então -F é o ideal.
        START_TIME_JOURNAL=$(echo "$SERVER_LOGS" | grep -m 1 -F "$LOG_START_CLIENT_PATTERN" | awk '{print $1}')
        
        # Extrai o timestamp do último cliente terminou de ser atendido
        # LOG_END_CLIENT_PATTERN contém regex ([0-9]+), então -E é necessário.
        END_TIME_JOURNAL=$(echo "$SERVER_LOGS" | grep -E "$LOG_END_CLIENT_PATTERN" | tail -n 1 | awk '{print $1}')

        if [ -z "$START_TIME_JOURNAL" ] || [ -z "$END_TIME_JOURNAL" ]; then
            echo "!!! ERRO: Não foi possível encontrar os timestamps de início/fim do atendimento nos logs do journald. Abortando." >&2
            echo "Logs do servidor durante este teste:" >&2
            echo "$SERVER_LOGS" >&2
            sudo kill -15 "$server_pid" >/dev/null 2>&1
            exit 1
        fi

        # Calcula a diferença de tempo usando dateutils.diff e formata para MM:SS
        # O programa dateutils.diff precisa ser instalado (sudo apt-get install dateutils)
        ELAPSED_TIME_MM_SS=$(dateutils.ddiff "$START_TIME_JOURNAL" "$END_TIME_JOURNAL" -f "%M:%S")

        # Mensagens de finalização da execução dos clientes (conforme PDF)
        # echo "" # Linha em branco para espaçamento
        echo ">>>>>>> ${num_clientes} clientes encerraram a conexão"
        # echo "" # Linha em branco para espaçamento
        echo ">>>>>>> Tempo para servir os ${num_clientes} clientes com o $nome_servidor_exec: ${ELAPSED_TIME_MM_SS}"
        if [[ "$nome_servidor_exec" == "ep4-servidor-inet_processos" ]]; then
            TIME_INET_PROCESSOS="$ELAPSED_TIME_MM_SS"
        elif [[ "$nome_servidor_exec" == "ep4-servidor-inet_threads" ]]; then
            TIME_INET_THREADS="$ELAPSED_TIME_MM_SS"
        elif [[ "$nome_servidor_exec" == "ep4-servidor-inet_muxes" ]]; then
            TIME_INET_MUXES="$ELAPSED_TIME_MM_SS"
        elif [[ "$nome_servidor_exec" == "ep4-servidor-unix_threads" ]]; then
            TIME_UNIX_THREADS="$ELAPSED_TIME_MM_SS"
        fi
        # --- Verificação de Sucesso Final para o Teste Atual ---
        if [ "$ALL_CLIENTS_GOT_RESPONSE" = false ] || [ "$CLIENT_CRITICAL_ERRORS_FOUND" = true ]; then
            echo "!!! ERRO: Teste de throughput para $nome_servidor_exec com arquivo ${tamanho_mb}MB falhou criticamente. Abortando." >&2
            # Tentar matar o servidor antes de sair
            sudo kill -15 "$server_pid" >/dev/null 2>&1
            exit 1 # Aborta imediatamente em caso de falha crítica
        fi

        # --- Envio de sinal 15 para o servidor (conforme PDF) ---
        echo "Enviando um sinal 15 para o servidor $nome_servidor_exec..."
        sudo kill -15 "$server_pid" >/dev/null 2>&1 # Envia sinal 15

        # Verifica se o servidor realmente encerrou
        for ((k=0; k<5; k++)); do # Tenta por até 5 segundos
            if ! pgrep -f "$nome_servidor_exec" >/dev/null; then
                break
            fi
            sleep 1
        done
        if pgrep -f "$nome_servidor_exec" >/dev/null; then
            echo "!!! ERRO: Servidor $nome_servidor_exec \(PID $server_pid\) não encerrou com sinal 15. Forçando kill -9." >&2
            sudo kill -9 "$server_pid" >/dev/null 2>&1
        fi
        # Não há pausa explícita aqui no fluxo do PDF entre o encerramento de um servidor e a subida do próximo
    done # Fim do loop de servidores

    # --- INÍCIO DO CÓDIGO A ADICIONAR ---
    # Após testar todos os servidores para o tamanho de arquivo atual, escrever no arquivo de dados
    echo "${tamanho_mb} ${TIME_INET_PROCESSOS} ${TIME_INET_THREADS} ${TIME_INET_MUXES} ${TIME_UNIX_THREADS}" >> "$DATA_FILE"
    # --- FIM DO CÓDIGO A ADICIONAR ---

done # Fim do loop de arquivos

# --- Mensagem final de geração de gráfico (Conforme PDF) ---
echo "" # Linha em branco para espaçamento
echo ">>>>>>> Gerando o gráfico de ${num_clientes} clientes com arquivos de: ${TAMANHOS_ARQUIVO_ARGS}MB"

# --- INÍCIO DO CÓDIGO PARA GERAR E EXECUTAR O GNUPLOT ---

# Define o nome do arquivo de configuração do gnuplot e o nome do PDF de saída
GPI_FILE="/tmp/ep4-resultados-${N_CLIENTS}.gpi"
GRAPH_OUTPUT_PDF="ep4-resultados-${N_CLIENTS}.pdf" # PDF final no diretório do script, conforme PDF

# Cria o arquivo de configuração do gnuplot usando um "here document"
cat << EOF > "$GPI_FILE"
set ydata time
set timefmt "%M:%S"
set format y "%M:%S"
set xlabel 'Dados transferidos por cliente (MB)'
set ylabel 'Tempo para atender ${N_CLIENTS} clientes concorrentes'
set term pdfcairo
set output "${GRAPH_OUTPUT_PDF}"
set grid
set key top left
plot "${DATA_FILE}" using 1:4 with linespoints title "Sockets da Internet: Mux de E/S",\\
 "${DATA_FILE}" using 1:3 with linespoints title "Sockets da Internet: Threads",\\
 "${DATA_FILE}" using 1:2 with linespoints title "Sockets da Internet: Processos",\\
 "${DATA_FILE}" using 1:5 with linespoints title "Sockets Unix: Threads"
EOF

# Executa o gnuplot com o arquivo de configuração gerado
echo "Executando gnuplot para gerar ${GRAPH_OUTPUT_PDF}..."
gnuplot "$GPI_FILE"

# Verifica se o PDF foi gerado com sucesso
if [ -f "$GRAPH_OUTPUT_PDF" ]; then
    echo "Gráfico ${GRAPH_OUTPUT_PDF} gerado com sucesso!"
else
    echo "!!! ERRO: Falha ao gerar o gráfico ${GRAPH_OUTPUT_PDF}. Verifique a instalação do gnuplot e suas dependências (ex: libcairo2-dev, libpango1.0-dev)." >&2
fi

# --- FIM DO CÓDIGO PARA GERAR E EXECUTAR O GNUPLOT ---

# --- Remoção de arquivos temporários (Requisito 2.8) ---
# ATENÇÃO: Para depuração (se você quiser manter os executáveis em /tmp/ para rodar manualmente),
for file_to_remove in "${ARQUIVOS_TESTE[@]}"; do
    rm -f "$file_to_remove"
done
# Remover executáveis compilados
rm -f /tmp/ep4-servidor-inet_processos \
      /tmp/ep4-servidor-inet_threads \
      /tmp/ep4-servidor-inet_muxes \
      /tmp/ep4-servidor-unix_threads \
      /tmp/ep4-cliente-inet \
      /tmp/ep4-cliente-unix

# --- INÍCIO DO CÓDIGO A ADICIONAR ---
# Remover arquivos temporários do gnuplot (.data e .gpi)
rm -f "$DATA_FILE" "$GPI_FILE"
# --- FIM DO CÓDIGO A ADICIONAR ---

exit 0 # Código de saída 0 para sucesso, conforme requisito 2.8