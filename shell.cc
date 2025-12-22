#include <cstdio>
#include <unistd.h>
#include "shell.hh"
#include <signal.h>
#include <sys/wait.h>

int yyparse(void);

void Shell::prompt() {
  if (isatty(0)) {
    printf("myshell>");
    fflush(stdout);
  }
  //fflush(stdout);
}
extern "C" void ctrlC_handle(int sig) {
  printf("\n");
  Shell::prompt();
  fflush(stdout);
}

extern "C" void zombie_handle(int sig) {
  int pid;
  while ((pid = waitpid(-1, NULL, WNOHANG)) > 0) { //NULL mean any status //WNOHANG is no block
    //printf("[%d] exited.\n", pid);
    //fflush(stdout);
  }
}
int main() {
  //2.1 Ctr-C
  struct sigaction sa;
  sa.sa_handler = ctrlC_handle;
  sigemptyset(&sa.sa_mask);
  sa.sa_flags = SA_RESTART;

  if(sigaction(SIGINT, &sa, NULL)){
    perror("sigaction");
    exit(2);
  }

  //2.2 Handle zombie
  sa.sa_handler = zombie_handle;
  sigemptyset(&sa.sa_mask);
  sa.sa_flags = SA_RESTART;
  if (sigaction(SIGCHLD, &sa, NULL)) {
    perror("sigchild");
    exit(2);
  }
  Shell::prompt();
  yyparse();
}