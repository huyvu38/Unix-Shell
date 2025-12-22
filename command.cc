#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <unistd.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <fcntl.h>
#include "command.hh"
#include "shell.hh"
void myunputc(int c);
extern int last_return_code;
extern pid_t last_pid;
extern std::string last_argument;

Command::Command() {
    // Initialize a new vector of Simple Commands
    _simpleCommands = std::vector<SimpleCommand *>();
    _outFile = NULL;
    _inFile = NULL;
    _errFile = NULL;
    _background = false;
    _append = false;
    _ambiguous = false;
}

void Command::insertSimpleCommand( SimpleCommand * simpleCommand ) {
    // add the simple command to the vector
    _simpleCommands.push_back(simpleCommand);
}

void Command::clear() {
    // deallocate all the simple commands in the command vector
    for (auto simpleCommand : _simpleCommands) {
        delete simpleCommand;
    }

    // remove all references to the simple commands we've deallocated
    // (basically just sets the size to 0)
    _simpleCommands.clear();

    if ( _outFile ) {
      delete _outFile;
    }
    _outFile = NULL;

    if ( _inFile ) {
      delete _inFile;
    }
    _inFile = NULL;

    if ( _errFile ) {
      delete _errFile;
    }
    _errFile = NULL;
    _background = false;
    _append = false;
    _ambiguous = false;
}

void Command::print() {
    printf("\n\n");
    printf("              COMMAND TABLE                \n");
    printf("\n");
    printf("  #   Simple Commands\n");
    printf("  --- ----------------------------------------------------------\n");

    int i = 0;
    // iterate over the simple commands and print them nicely
    for ( auto & simpleCommand : _simpleCommands ) {
        printf("  %-3d ", i++ );
        simpleCommand->print();
    }

    printf( "\n\n" );
    printf( "  Output       Input        Error        Background\n" );
    printf( "  ------------ ------------ ------------ ------------\n" );
    printf( "  %-12s %-12s %-12s %-12s\n",
            _outFile?_outFile->c_str():"default",
            _inFile?_inFile->c_str():"default",
            _errFile?_errFile->c_str():"default",
            _background?"YES":"NO");
    printf( "\n\n" );
}

void Command::execute() {
    // Don't do anything if there are no simple commands
    if ( _simpleCommands.size() == 0 || _ambiguous == true) {
        Shell::prompt();
        return;
    }

    // Print contents of Command data structure
    //print();

    // Add execution here
    // For every simple command fork a new process
    // Setup i/o redirection
    // and call exec

    //EXIT

    if(strcmp(_simpleCommands[0]->_arguments[0]->c_str(),"exit") == 0){
      printf("Good bye!!\n");
      exit(1);
    }

    //2.6 setenv

    if ((_simpleCommands.size() == 1) && (strcmp(_simpleCommands[0]->_arguments[0]->c_str(), "setenv") == 0)) {
      if (_simpleCommands[0]->_arguments.size() != 3) {
        fprintf(stderr, "setenv should take 2 arguments\n");
      } else {
        // 1 mean overwrite
        setenv(_simpleCommands[0]->_arguments[1]->c_str(), _simpleCommands[0]->_arguments[2]->c_str(), 1);
      }
      clear();
      Shell::prompt();
      return;
    }

    //2.6 unsetenv

    if ((_simpleCommands.size() == 1) && (strcmp(_simpleCommands[0]->_arguments[0]->c_str(), "unsetenv") == 0)) {
      if (_simpleCommands[0]->_arguments.size() != 2) {
        fprintf(stderr, "unsetenv should take 1 arguments\n");
      } else {
        unsetenv(_simpleCommands[0]->_arguments[1]->c_str());
      }
      clear();
      Shell::prompt();
      return;
    }
    //2.6 cd
    if ((_simpleCommands.size() == 1) && (strcmp(_simpleCommands[0]->_arguments[0]->c_str(), "cd") == 0)) {
      const char* dir;
      std::string expanded_path;
      if (_simpleCommands[0]->_arguments.size() >= 2) {
        const char *arg = _simpleCommands[0]->_arguments[1]->c_str();
        if (arg[0] == '$') {
          const char *var_name_ptr = arg + 1;
          if (*var_name_ptr == '{' && arg[strlen(arg) - 1] == '}') {
            std::string var_name(var_name_ptr + 1, arg + strlen(arg) - 1);
            const char *value = getenv(var_name.c_str());
            if (value) {
              expanded_path = value;
            } else {
              expanded_path = "";
            }
         } else {
           const char *value = getenv(var_name_ptr);
           if (value) {
             expanded_path = value;
           } else {
             expanded_path = "";
           }
         }
         dir = expanded_path.c_str();
       } else {
         dir = arg;
       }
     } else {
        // No argument, default to HOME
        dir = getenv("HOME");
        if (!dir) {
          fprintf(stderr, "cd: HOME not set\n");
          clear();
          Shell::prompt();
          return;
        }
     }
     if (chdir(dir) != 0) {
       fprintf(stderr, "cd: can't cd to %s\n", dir);
     }
     clear();
     Shell::prompt();
     return;
    }
    int defaultin = dup(0);
    int defaultout = dup(1);
    int defaulterr = dup(2);
    // I/O Redirection
    int fdin = 0;
    int fdout = 0;
    int fderr = 0;
    if (_inFile) {
      //redirect from file
      fdin = open(_inFile->c_str(), O_RDONLY);
    } else {
      fdin = dup(defaultin);
    }
    for (size_t i = 0; i < _simpleCommands.size(); i++) {
      //Redirect input
      dup2(fdin, 0); // now child's stdin = fdin
      close(fdin);
      if (i == _simpleCommands.size() - 1) {
        if (_outFile) {
          //0644 is rw--r--r
          if (_append) {
            fdout = open(_outFile->c_str(), O_WRONLY | O_CREAT | O_APPEND, 0644);
          } else {
            fdout = open(_outFile->c_str(), O_WRONLY | O_CREAT | O_TRUNC, 0644);
          }
        } else {
          fdout = dup(defaultout);
        }
        //Redirect output
        dup2(fdout, 1);
        close(fdout);

        if (_errFile) {
          //0644 is rw--r--r
          if (_append) {
            fderr = open(_errFile->c_str(), O_WRONLY | O_CREAT | O_APPEND, 0644);
          } else {
            fderr = open(_errFile->c_str(), O_WRONLY | O_CREAT | O_TRUNC, 0644);
          }
        } else {
          fderr = dup(defaulterr);
        }
        //Redirect error
        dup2(fderr, 2);
        close(fderr);
      } else {
        //Create pipe
        int fdpipe[2];
        pipe(fdpipe);
        fdout = fdpipe[1];
        fdin = fdpipe[0];
      }

      //Redirect output to pipe
      dup2(fdout, 1);
      close(fdout);
      //Store the last argument
      last_argument = *_simpleCommands[i]->_arguments[_simpleCommands[i]->_arguments.size() - 1];
      signal(SIGINT, SIG_IGN);
      int ret = fork();
      if (ret == 0) {
        //Child process
        signal(SIGINT, SIG_DFL);
        //2.6 printenv
        if (strcmp(_simpleCommands[i]->_arguments[0]->c_str(), "printenv") == 0 ) {
          extern char **environ;
          int i = 0;
          while (environ[i] != NULL) {
            printf("%s\n" , environ[i]);
            i++;
          }
          exit(0); //terminate the child
        }
        size_t argc = _simpleCommands[i]->_arguments.size();
        char ** argv = new char* [argc + 1];
        for (size_t j = 0; j < argc; j++) {
          argv[j] = (char *)(_simpleCommands[i]->_arguments[j]->c_str());
        }
        argv[argc] = NULL;
        execvp(argv[0], argv);
        perror("execvp");
        exit(1);
      } else if (ret > 0) {
        //Parent process
        //Foreground and wait for child process to finish
        if (_background == false) {
          int status;
          waitpid(ret, &status, 0);
          if (WIFSIGNALED(status) && WTERMSIG(status) == SIGINT) {
            write(1, "\n", 1);
          }
          if (WIFEXITED(status)) {
            //Checks if the child terminated normally
            last_return_code = WEXITSTATUS(status);
          } else {
            last_return_code = 1;
          }
        } else {
          last_pid = ret;
        }
      } else {
        //Error
        perror("fork");
      }
    }
    //Restore
    dup2(defaultin, 0);
    dup2(defaultout, 1);
    dup2(defaulterr, 2);
    close(defaultin);
    close(defaultout);
    close(defaulterr);

    // Clear to prepare for next command
    clear();

    // Print new prompt
    Shell::prompt();
}

SimpleCommand * Command::_currentSimpleCommand;