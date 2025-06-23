/* Servidor de echo usando sockets da Internet e multiplexação de E/S
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

int main() {
    int listenfd;
    int connfd;
    struct sockaddr_in servaddr;

    pid_t pid;

    char recvline[MAXLINE+1];
    ssize_t n;

    int i, maxi, maxfd, sockfd;
    int nready, client[FD_SETSIZE];
    fd_set rset, allset;

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

    maxfd = listenfd;
    maxi = -1;
    for (i = 0; i < FD_SETSIZE; i++)
        client[i] = -1;
    FD_ZERO(&allset);
    FD_SET(listenfd, &allset);

    for ( ; ; ) {
        rset = allset;
        nready = select(maxfd+1, &rset, NULL, NULL, NULL);
        if (nready == -1) {
            syslog(LOG_ERR|LOG_USER,"Erro no select :-( [%m]\n");
            exit(3);
        }

        if (FD_ISSET(listenfd, &rset)) {
            connfd = accept(listenfd, (struct sockaddr *) NULL, NULL);
            if (connfd == -1) {
                syslog(LOG_ERR|LOG_USER,"Erro no accept :-( [%m]\n");
                exit(4);
            }
            else
                syslog(LOG_INFO|LOG_USER,"Passou pelo accept :-)\n");

            for (i = 0; i < FD_SETSIZE; i++)
                if (client[i] < 0) {
                    client[i] = connfd;
                    break;
                }
            if (i == FD_SETSIZE) {
                syslog(LOG_ERR|LOG_USER,"Muitos clientes! :-(\n");
                exit(5);
            }

            FD_SET(connfd, &allset);
            if (connfd > maxfd)
                maxfd = connfd;
            if (i > maxi)
                maxi = i;

            if (--nready <= 0)
                continue;
        }

        for (i = 0; i <= maxi; i++) {
            if ( (sockfd = client[i]) < 0)
                continue;

            if (FD_ISSET(sockfd, &rset)) {
                if ((n=read(sockfd, recvline, MAXLINE)) <= 0) {
                    if (close(sockfd)) {
                        syslog(LOG_ERR|LOG_USER,"Erro no close :-( [%m]\n");
                        exit(6);
                    }
                    FD_CLR(sockfd, &allset);
                    client[i] = -1;
                    syslog(LOG_INFO|LOG_USER,"Cliente do socket %d provavelmente enviou um exit\n",i);
                }
                else {
                    recvline[n]=0;
                    if (write(sockfd, recvline, strlen(recvline)) == -1) {
                        syslog(LOG_ERR|LOG_USER,"Erro no write :-( [%m]\n");
                        exit(7);
                    }
                }
                
                if (--nready <= 0)
                    break;
            }
        }
    }
    
    exit(0);
}
