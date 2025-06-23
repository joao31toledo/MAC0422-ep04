/* Servidor de echo usando sockets da Internet e múltiplos processos
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
#include <sys/wait.h>
#include <fcntl.h>

#define MAXLINE 100
#define LISTENQ 512

#define MAXFD 64

void sig_chld(int signo) {
    pid_t pid;
    int status;
    
    while ( (pid = waitpid(-1, &status, WNOHANG)) > 0 )
        fprintf(stderr,"Filho %d terminou\n", pid);
    
    return;
}

int main() {
    int listenfd;
    int connfd;
    struct sockaddr_in servaddr;

    int i;

    pid_t pid;

    char recvline[MAXLINE+1];
    ssize_t n;

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
    signal(SIGCHLD, sig_chld);
    syslog(LOG_INFO|LOG_USER,"Servidor de echo no ar! :-)\n");

    i=0;
    for ( ; ; ) {
        connfd = accept(listenfd, (struct sockaddr *) NULL, NULL);
        if (connfd == -1) {
            syslog(LOG_ERR|LOG_USER,"Erro no accept :-( [%m]\n");
            exit(3);
        }
        else
            syslog(LOG_INFO|LOG_USER,"Passou pelo accept :-)\n");

        if ((pid = fork()) == 0) {
            close(listenfd);

            while ((n=read(connfd, recvline, MAXLINE)) > 0) {
                recvline[n]=0;
                if (write(connfd, recvline, strlen(recvline)) == -1) {
                    syslog(LOG_ERR|LOG_USER,"Erro no write :-( [%m]\n");
                    exit(5);
                }
            }
   
            if (close(connfd)) {
                syslog(LOG_ERR|LOG_USER,"Erro no close :-( [%m]\n");
                exit(6);
            }
            syslog(LOG_INFO|LOG_USER,"Cliente do PID %d provavelmente enviou um exit\n",getpid());
            exit(0);
        }
        else
            if (close(connfd)) {
                syslog(LOG_ERR|LOG_USER, "Erro no close :-( [%m]\n");
                exit(6);
            }
    }
    exit(0);
}
