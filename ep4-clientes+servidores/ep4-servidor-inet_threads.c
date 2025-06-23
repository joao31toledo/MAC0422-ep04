/* Servidor de echo usando sockets da Internet e múltiplas threads
 * Código a ser usado no EP4 da disciplina MAC0422 em 2025.1
 * ministrada pelo Prof. Daniel Macêdo Batista na USP 
 */

#include <sys/socket.h>
#include <strings.h>
#include <string.h>
#include <arpa/inet.h>
#include <stdio.h>
#include <unistd.h>
#include <stdlib.h>
#include <pthread.h>
#include <syslog.h>
#include <signal.h>
#include <fcntl.h>

#define MAXLINE 100
#define LISTENQ 512

#define MAXFD 64

void * servidor (void * connfd) {
    char recvline[MAXLINE+1];
    ssize_t n;

    int * thread_connfd = (int *) connfd;
    
    while ((n=read(*thread_connfd, recvline, MAXLINE)) > 0) {
        recvline[n]=0;
        if (write(*thread_connfd, recvline, strlen(recvline)) == -1) {
            syslog(LOG_ERR|LOG_USER,"Erro no write :-( [%m]\n");
            exit(5);
        }
    }
   
    if (close(*thread_connfd)) {
        syslog(LOG_ERR|LOG_USER,"Erro no close :-( [%m]\n");
        exit(6);
    }
    syslog(LOG_INFO|LOG_USER,"Cliente da TID %lu provavelmente enviou um exit\n",pthread_self());
 
    return NULL;
}

int main() {
    int listenfd;
    int connfd[LISTENQ];
    struct sockaddr_in servaddr;

    int i;
    pthread_t tid[LISTENQ];

    pid_t pid;

    syslog(LOG_INFO|LOG_USER,"Início...\n");

    if ((pid = fork()) < 0)
        return (-1);
    else if (pid)
        _exit(0);
    syslog(LOG_INFO|LOG_USER,"Primeiro processo filho criado...\n");
 
    if (setsid() < 0)
        return(-1);
    syslog(LOG_INFO|LOG_USER,"Nova sessão e novo grupo criados...\n");
    
    if (signal(SIGHUP, SIG_IGN) == SIG_ERR)
        return(-1);
    syslog(LOG_INFO|LOG_USER,"SIGHUP ignorado...\n");

    if ((pid = fork()) < 0)
        return (-1);
    else if (pid)
        _exit(0);
    syslog(LOG_INFO|LOG_USER,"Segundo processo filho criado...\n");
    
    chdir("/");
    syslog(LOG_INFO|LOG_USER,"cwd do processo alterado para o /...\n");
    
    for(i=0;i<MAXFD;i++)
        close(i);
    syslog(LOG_INFO|LOG_USER,"64 descritores fechados...\n");
   
    closelog();
    open("/dev/null", O_RDONLY);
    open("/dev/null", O_RDWR);
    open("/dev/null", O_RDWR);
    syslog(LOG_INFO|LOG_USER,"0, 1 e 2 apontados para /dev/null...\n");
    
    listenfd = socket(AF_INET, SOCK_STREAM, 0);
    
    bzero(&servaddr, sizeof(servaddr));
    servaddr.sin_family = AF_INET;
    servaddr.sin_addr.s_addr = htonl(INADDR_ANY);
    servaddr.sin_port = htons(1500);
    
    if (bind(listenfd, (struct sockaddr *) &servaddr, sizeof(servaddr))) {
        syslog(LOG_ERR|LOG_USER,"Erro no bind :-( [%m]\n");
        exit(1);
    }
    if (listen(listenfd, LISTENQ)) {
        syslog(LOG_ERR|LOG_USER,"Erro no listen :-( [%m]\n");
        exit(2);
    }
    syslog(LOG_INFO|LOG_USER,"Servidor de echo no ar! :-)\n");

    i=0;
    for ( ; ; ) {
        connfd[i] = accept(listenfd, (struct sockaddr *) NULL, NULL);
        if (connfd[i] == -1) {
            syslog(LOG_ERR|LOG_USER,"Erro no accept :-( [%m]\n");
            exit(3);
        }
        else
            syslog(LOG_INFO|LOG_USER,"Passou pelo accept :-)\n");
        if (pthread_create(&tid[i], NULL, servidor, &(connfd[i]))) {
            syslog(LOG_ERR|LOG_USER,"Erro no pthread_create :-(\n");
            exit(6);
        }
        if (pthread_detach(tid[i])) {
            syslog(LOG_ERR|LOG_USER,"Erro no pthread_detach :-(\n");
            exit(7);
        }
        i=(i+1)%LISTENQ;
    }
    
    exit(0);
}
