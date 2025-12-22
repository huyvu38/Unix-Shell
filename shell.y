%code requires
{
#include <string>
#include <string.h>
#include <regex.h>
#include <dirent.h>
#include <algorithm>
#include <cstring>


#if __cplusplus > 199711L
#define register      // Deprecated in C++11 so remove the keyword
#endif

#define MAXFILENAME 1024
}

%union
{
  char        *string_val;
  // Example of using a c++ type in yacc
  std::string *cpp_string;
}

%token <cpp_string> WORD
%token NOTOKEN GREAT NEWLINE LESS PIPE AMPERSAND GREATGREAT GREATAMPERSAND GREATGREATAMPERSAND TWOGREAT

%{
//#define yylex yylex
#include <cstdio>
#include "shell.hh"
#include <cstring>
#include <regex.h>
#include <dirent.h>
#include <sys/types.h>
#include <assert.h>
#include <algorithm>

void yyerror(const char * s);
void expandWildcardsIfNecessary(char * arg);
void expandWildcard(char * prefix, char * suffix);
bool cmpfunction(std::string *i, std::string *j);
static std::vector<std::string *> finalArray = std::vector<std::string *>();
int yylex();

%}

%%

goal:
  commands
  ;

commands:
  command
  | commands command
  ;

command: simple_command
       ;

simple_command:
  pipe_list iomodifier_opt_list background_opt NEWLINE {
    //printf("   Yacc: Execute command\n");
    Shell::_currentCommand.execute();
  }
  | NEWLINE
  | error NEWLINE {
    yyerrok;
  }
  ;

command_and_args:
  command_word argument_list {
    Shell::_currentCommand.insertSimpleCommand( Command::_currentSimpleCommand );
  }
  ;

argument_list:
  argument_list argument
  | /* can be empty */
  ;

argument:
  WORD {
    char *arg = (char*) $1->c_str();
    char *empty = (char *)"";
    if (strchr(arg, '*') || strchr(arg, '?')) {
      expandWildcard(empty, arg);
    } else {
      Command::_currentSimpleCommand->insertArgument( $1 );
    }
  }
  ;

command_word:
  WORD {
    //printf("   Yacc: insert command \"%s\"\n", $1->c_str());
    //2.3: Exit
    /*
    if (strcmp($1->c_str(), "exit") == 0 ) {
      //tty_reset_mode();
      printf("Good Bye!!\n");
      exit(1);
    }
    */
    Command::_currentSimpleCommand = new SimpleCommand();
    Command::_currentSimpleCommand->insertArgument( $1 );
  }
  ;


iomodifier_opt:
  GREAT WORD {
    //printf("   Yacc: insert output \"%s\"\n", $2->c_str());

    if (Shell::_currentCommand._outFile != NULL) {
      fprintf(stderr, "Ambiguous output redirect.\n");
      Shell::_currentCommand._ambiguous = true;
    }
    Shell::_currentCommand._outFile = $2;
  }

  | LESS WORD {
    //printf("   Yacc: insert input \"%s\"\n", $2->c_str());
    if (Shell::_currentCommand._inFile != NULL) {
      fprintf(stderr, "Ambiguous output redirect.\n");
      Shell::_currentCommand._ambiguous = true;
    }
    Shell::_currentCommand._inFile = $2;
  }

  | TWOGREAT WORD {
    //printf("   Yacc: insert error \"%s\"\n", $2->c_str());
    if (Shell::_currentCommand._errFile != NULL) {
      fprintf(stderr, "Ambiguous output redirect.\n");
      Shell::_currentCommand._ambiguous = true;
    }
    Shell::_currentCommand._errFile = $2;
  }

  | GREATAMPERSAND WORD {
    //printf("   Yacc: insert output and error \"%s\"\n", $2->c_str());
    if (Shell::_currentCommand._outFile != NULL) {
      fprintf(stderr, "Ambiguous output redirect.\n");
      Shell::_currentCommand._ambiguous = true;
    }
    Shell::_currentCommand._outFile = new std::string(*$2);
    Shell::_currentCommand._errFile = new std::string(*$2);
    //Shell::_currentCommand._outFile = $2;
    //Shell::_currentCommand._errFile = $2;
  }

  | GREATGREAT WORD {
    //printf("   Yacc: insert append output \"%s\"\n", $2->c_str());
    if (Shell::_currentCommand._outFile != NULL) {
      fprintf(stderr, "Ambiguous output redirect.\n");
      Shell::_currentCommand._ambiguous = true;
    }
    Shell::_currentCommand._outFile = $2;
    Shell::_currentCommand._append = true;
  }

  | GREATGREATAMPERSAND WORD {
    //printf("   Yacc: insert append output & error \"%s\"\n", $2->c_str());
    if (Shell::_currentCommand._outFile != NULL) {
      fprintf(stderr, "Ambiguous output redirect.\n");
      Shell::_currentCommand._ambiguous = true;
    }
    Shell::_currentCommand._outFile = new std::string(*$2);
    Shell::_currentCommand._errFile = new std::string(*$2);
    //Shell::_currentCommand._outFile = $2;
    //Shell::_currentCommand._errFile = $2;
    Shell::_currentCommand._append = true;
  }
;

iomodifier_opt_list:
  iomodifier_opt_list iomodifier_opt
  | /* empty */
  ;

pipe_list:
  pipe_list PIPE command_and_args
  | command_and_args
  ;


background_opt:
  AMPERSAND {
    Shell::_currentCommand._background = true;
  }
  |
  ;


%%

void
yyerror(const char * s)
{
  fprintf(stderr,"%s", s);
}

void expandWildcard(char *prefix, char *suffix) {
  // Base case: no more suffix
  if (suffix[0] == 0) {
    Command::_currentSimpleCommand->insertArgument(new std::string(prefix));
    return;
  }

  // Split current suffix into first path component and remaining suffix
  char component[MAXFILENAME];
  char *s = strchr(suffix, '/');
  if (s != NULL) {
    // Copy the part before '/' into component
    strncpy(component, suffix, s - suffix);
    component[s - suffix] = 0;
    if (component[0] == 0) {
      // Handles "//" or leading '/'
      component[0] = '/';
      component[1] = 0;
    }
    suffix = s + 1;
  } else {
    strcpy(component, suffix);
    suffix = suffix + strlen(suffix);
  }
  if (strchr(component, '*') == NULL && strchr(component, '?') == NULL) {
    char newPrefix[MAXFILENAME];
    // Build new prefix
    if (prefix[0] == 0) {
      sprintf(newPrefix, "%s", component);
    } else if (prefix[0] == '/' && strlen(prefix) == 1) {
      sprintf(newPrefix, "/%s", component);
    } else {
      sprintf(newPrefix, "%s/%s", prefix, component);
    }
    expandWildcard(newPrefix, suffix);
    return;
  }

  // Case 2: component contains wildcards
  char *reg = (char*) malloc(2 * strlen(component) + 10);
  char *a = component;
  char *r = reg;
  *r = '^'; // match from beginning
  r++;
  while (*a) {
    if (*a == '*') {
      *r++ = '.';
      *r++ = '*';
    } else if (*a == '?') {
      *r++ = '.';
    } else if (*a == '.') {
      *r++ = '\\';
      *r++ = '.';
    } else {
      *r++ = *a;
    }
    a++;
  }
  *r = '$'; // match to end
  r++;
  *r = 0;

  regex_t re;
  if (regcomp(&re, reg, REG_EXTENDED | REG_NOSUB) != 0) {
    perror("compile");
    free(reg);
    return;
  }


  // Determine which directory to read
  char dirName[MAXFILENAME];
  if (prefix[0] == 0) {
    strcpy(dirName, ".");
  } else {
    strcpy(dirName, prefix);
  }

  DIR *dir = opendir(dirName);
  if (!dir) {
    regfree(&re);
    free(reg);
    return;
  }

  int maxEntries = 20;
  int nEntries = 0;
  char **array = (char**) malloc(maxEntries * sizeof(char*));
  struct dirent *ent;

  while ((ent = readdir(dir)) != NULL) {
     // Skip hidden files unless pattern explicitly starts with '
    if (ent->d_name[0] == '.' && component[0] != '.') {
      continue;
    }
    char newPrefix[MAXFILENAME];
    // Check if filename matches the regex
    if (regexec(&re, ent->d_name, 0, NULL, 0) == 0) {
      if (nEntries == maxEntries) {
        maxEntries *= 2;
        array = (char**) realloc(array, maxEntries * sizeof(char*));
        assert(array != NULL);
      }
      if (prefix[0] == 0) {
        sprintf(newPrefix, "%s", ent->d_name);
      } else if (prefix[0] == '/' && strlen(prefix) == 1) {
        sprintf(newPrefix, "/%s", ent->d_name);
      } else {
        sprintf(newPrefix, "%s/%s", prefix, ent->d_name);
      }
      array[nEntries++] = strdup(newPrefix);
    }
  }
  closedir(dir);
  regfree(&re);
  free(reg);

   // Sort matches alphabetically
  for (int i = 0; i < nEntries - 1; i++) {
    for (int j = i + 1; j < nEntries; j++) {
      if (strcmp(array[i], array[j]) > 0) {
        char *temp = array[i];
        array[i] = array[j];
        array[j] = temp;
      }
    }
  }
  for (int i = 0; i < nEntries; i++) {
    expandWildcard(array[i], suffix);
    free(array[i]);
  }
  free(array);
}


void expandWildcardsIfNecessary(char * arg) {
  // 1. Check if argument contains '*' or '?'
  if (strchr(arg, '*') == NULL && strchr(arg, '?') == NULL) {
    Command::_currentSimpleCommand->insertArgument(new std::string(arg));
    return;
  }

  // 2. Convert wildcard to regular expression
  char * reg = (char*) malloc(2 * strlen(arg) + 10);
  char * a = arg;
  char * r = reg;
  *r = '^';
  r++;

  while (*a) {
    if (*a == '*') {
      *r = '.';
      r++;
      *r = '*';
      r++;
    } else if (*a == '?') {
      *r ='.';
      r++;
    } else if (*a == '.') {
      *r = '\\';
      r++;
      *r = '.';
      r++;
    } else {
      *r = *a;
      r++;
    }
    a++;
  }

  // Match end of line
  *r = '$';
  r++;
  *r = 0;

  // 3. compile regular expression.
  regex_t re;
  int expbuf = regcomp(&re, reg, REG_EXTENDED | REG_NOSUB);
  if (expbuf != 0) {
    perror("compile");
    return;
  }

  // 4. Open dir
  DIR * dir = opendir(".");
  if (dir == NULL) {
    perror("opendir");
    return;
  }

  // 5. Collect matches
  int maxEntries = 20;
  int nEntries = 0;
  char **array = (char **) malloc(maxEntries * sizeof(char *));
  struct dirent *ent;

  while ((ent = readdir(dir)) != NULL) {
    // Hidden file handling
    if (ent->d_name[0] == '.' && arg[0] != '.') {
       continue;
    }
    // Match regex
    if (regexec(&re, ent->d_name, 0, NULL, 0) == 0) {
      // Increase entries
      if (nEntries == maxEntries) {
        maxEntries *= 2;
        array = (char **) realloc(array, maxEntries * sizeof(char *));
        assert(array != NULL);
      }
      array[nEntries] = strdup(ent->d_name);
      nEntries++;
      }
    }
    closedir(dir);
    regfree(&re);
    free(reg);

    // 6. Sort entries
    for (int i = 0; i < nEntries - 1; i++) {
      for (int j = i + 1; j < nEntries; j++) {
        if (strcmp(array[i], array[j]) > 0) {
          char * temp = array[i];
          array[i] = array[j];
          array[j] = temp;
        }
      }
    }

    for (int i = 0; i < nEntries; i++) {
      Command::_currentSimpleCommand->insertArgument(new std::string(array[i]));
    }

    free(array);

}

#if 0
main()
{
  yyparse();
}
#endif