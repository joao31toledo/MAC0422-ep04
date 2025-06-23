#!/bin/bash

# Define o nome do executável e a porta
NOME_SERVIDOR="ep4-servidor-inet_processos"
CAMINHO_EXECUTAVEL="/tmp/$NOME_SERVIDOR"
PORTA_INET="1500" # Porta usada pelo servidor inet_processos

echo "--- Script de Teste Simplificado: $NOME_SERVIDOR ---"

# --- Parte 1: Compilação do servidor ---
echo "Compilando $NOME_SERVIDOR"
gcc ep4-clientes+servidores/ep4-servidor-inet_processos.c -o "$CAMINHO_EXECUTAVEL" -Wall

if [ ! -f "$CAMINHO_EXECUTAVEL" ]; then
    echo "!!! ERRO: Falha na compilação de $NOME_SERVIDOR."
    exit 1
fi

# --- Parte 2: Limpeza de instâncias anteriores ---
echo "Verificando e matando instâncias anteriores de $NOME_SERVIDOR..."
pids_existentes=$(pgrep -f "$NOME_SERVIDOR")
if [ -n "$pids_existentes" ]; then
    echo "  --> Encontrado(s) PID(s) anterior(es): $pids_existentes. Matando-o(s)..."
    sudo kill -9 $pids_existentes
    sleep 3 # Tempo para o sistema processar a morte
    if pgrep -f "$NOME_SERVIDOR" > /dev/null; then
        echo "  !!! ERRO: Processo $NOME_SERVIDOR (PID(s) $pids_existentes) não terminou após kill -9. Abortando."
        exit 1
    else
        echo "  Instâncias anteriores encerradas."
    fi
else
    echo "  Nenhuma instância anterior encontrada."
fi

# Garantir que a porta esteja realmente livre antes de iniciar (verificação extra)
echo "Verificando se a porta $PORTA_INET está livre..."
if sudo lsof -i :$PORTA_INET > /dev/null; then
    echo "  !!! AVISO: Porta $PORTA_INET ainda em uso por outro processo. Isso pode causar problemas."
    # Pode-se adicionar aqui um `sudo lsof -i :$PORTA_INET` para mostrar o culpado.
    # Por enquanto, vamos tentar seguir, mas pode falhar.
fi

# --- Parte 3: Início do Servidor ---
echo "Subindo o servidor $NOME_SERVIDOR..."
"$CAMINHO_EXECUTAVEL" &
SERVER_PID_PAI=$! # Captura o PID do processo pai

# --- Parte 4: Verificação de Inicialização Robusta ---
echo "Verificando se $NOME_SERVIDOR está ouvindo na porta $PORTA_INET..."
SERVER_UP=false
SERVER_PID_DAEMON=""

for i in $(seq 1 10); do # Tenta por até 10 segundos
    # Procura por qualquer processo com o nome truncado 'ep4-servi' ouvindo na porta
    if sudo lsof -i :$PORTA_INET | grep -q "ep4-servi"; then
        SERVER_UP=true
        # Tenta pegar o PID do processo que está ouvindo na porta
        SERVER_PID_DAEMON=$(sudo lsof -t -i :$PORTA_INET | head -n 1)
        break
    fi
    sleep 1
done

if [ "$SERVER_UP" = true ]; then
    if [ -n "$SERVER_PID_DAEMON" ] && ps -p "$SERVER_PID_DAEMON" > /dev/null; then
        echo "  Servidor $NOME_SERVIDOR subiu e está ouvindo na porta $PORTA_INET com PID: $SERVER_PID_DAEMON"
        server_pid="$SERVER_PID_DAEMON" # Define o PID principal para operações futuras (ex: matar)
    else
        echo "  !!! ERRO: Servidor $NOME_SERVIDOR subiu, mas não conseguimos encontrar o PID ativo (`$SERVER_PID_DAEMON`). Verifique manualmente."
        exit 1
    fi
else
    echo "  !!! ERRO: Servidor $NOME_SERVIDOR não subiu e não está ouvindo na porta $PORTA_INET em 10s. Falha na inicialização."
    exit 1
fi

# --- Parte 5: Encerramento do Servidor (após teste, aqui apenas para demonstração) ---
echo "Enviando sinal 15 para encerrar o servidor $NOME_SERVIDOR (PID $server_pid)..."
sudo kill -15 "$server_pid"

sleep 2 # Dá um tempo para o servidor encerrar graciosamente

if ps -p "$server_pid" > /dev/null; then
    echo "  !!! AVISO: Servidor $NOME_SERVIDOR (PID $server_pid) não encerrou com sinal 15. Forçando encerramento com sinal 9."
    sudo kill -9 "$server_pid"
    sleep 3
    if ps -p "$server_pid" > /dev/null; then
        echo "  !!! ERRO CRÍTICO: Servidor $NOME_SERVIDOR (PID $server_pid) ainda rodando após kill -9. Abortando."
        exit 1
    else
        echo "  Servidor $NOME_SERVIDOR (PID $server_pid) encerrado à força."
    fi
else
    echo "  Servidor $NOME_SERVIDOR (PID $server_pid) encerrado com sucesso."
fi

echo "--- Teste Simplificado Concluído ---"