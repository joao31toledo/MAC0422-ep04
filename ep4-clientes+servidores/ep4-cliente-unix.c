/* Cliente de echo usando sockets de domínio Unix
 * Código a ser usado no EP4 da disciplina MAC0422 em 2025.1
 * ministrada pelo Prof. Daniel Macêdo Batista na USP 
 */

#include <stdio.h>
#include <strings.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>

#include <sys/types.h>
#include <sys/uio.h>

#define MAXLINE 100

#define SOCKET_NAME "/tmp/uds-echo.sock"

int main(int argc, char **argv) {
    int sockfd;
    char recvline[MAXLINE + 1];
    char sendline[MAXLINE + 1];
    struct sockaddr_un servaddr;
    ssize_t n;
    int bye;
   
    sockfd = socket(AF_UNIX, SOCK_STREAM, 0);
    
    bzero(&servaddr, sizeof(servaddr));
    servaddr.sun_family = AF_UNIX;
    strcpy(servaddr.sun_path,SOCKET_NAME);
    
    if (connect(sockfd, (struct sockaddr *) &servaddr, sizeof(servaddr))) {
        fprintf(stderr,"Erro no connect :-(\n");
        exit(2);
    }
    else
        fprintf(stderr,"Passou pelo connect...\n");

    bye=0;
    while (!bye) {
        if (fgets(sendline,MAXLINE+1,stdin) == NULL) {
            fprintf(stderr,"Erro no fgets... ou o arquivo chegou no fim\n");
            exit(3);
        }
        if (!strcmp(sendline,"exit\n")) {
            bye=1;
            close(sockfd);
        }
        else {
            if (write(sockfd,sendline,strlen(sendline)) == -1) {
                fprintf(stderr,"Erro no write...\n");
                exit(4);
            }
            if ((n=read(sockfd,recvline,MAXLINE)) < 0) {
                fprintf(stderr,"Erro no read...\n");
                exit(5);
            }
            recvline[n]=0;
            fputs(recvline, stdout);
        }
    }
    fprintf(stderr,"[Encerrando a execução...]\n");

    exit (0);
}
