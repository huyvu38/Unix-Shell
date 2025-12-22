%x src

%{

#include <cstring>
#include "y.tab.hh"
#include <sys/wait.h>

static void yyunput (int c,char *buf_ptr  );
int last_return_code = 0;
pid_t last_pid = 0;
std::string last_argument = "";

void myunputc(int c) {
  unput(c);
}

extern "C" char * read_line();

int mygetc(FILE * f) {
  static char *p;
  char ch;

  if (!isatty(0)) {
    return getc(f);
  }

  if (p == NULL || *p == 0) {
    char * s = read_line();
    p =s;
  }
  ch = *p;
  p++;

  return ch;
}

#undef getc
#define getc(f) mygetc(f)

%}

%option noyywrap

%%

\n {
  return NEWLINE;
}

[ \t] {

}

"|" {
  return PIPE;
}

"&" {
  return AMPERSAND;
}

"<" {
  return LESS;
}

">" {
  return GREAT;
}

">&" {
  return GREATAMPERSAND;
}

">>" {
  return GREATGREAT;
}

">>&" {
  return GREATGREATAMPERSAND;
}

"2>" {
  return TWOGREAT;
}

\$\([^\n]*\) {
  std::string cmd(yytext);
  cmd = cmd.substr(2, cmd.size() - 3); // remove $( and )

  int pin[2];  // parent → child
  int pout[2]; // child → parent
  pipe(pin);
  pipe(pout);

  int ret = fork();
  if (ret == 0) { // child
    dup2(pin[0], 0);  // stdin from parent
    dup2(pout[1], 1); // stdout to parent
    close(pin[0]);
    close(pin[1]);
    close(pout[0]);
    close(pout[1]);
    char *argv[] = { (char*)"/proc/self/exe", NULL };
    execvp("/proc/self/exe", argv);
    perror("execvp");
    exit(1);
  } else if (ret < 0) {
    perror("fork");
    exit(1);
  }

  // parent
  close(pin[0]);
  close(pout[1]);

  // write command to child
  write(pin[1], cmd.c_str(), cmd.size());
  write(pin[1], "\n", 1);
  close(pin[1]);

  // read output from child
  char buffer[4096];
  int i = 0;
  char c;
  while (read(pout[0], &c, 1) > 0 && i < 4095) {
    if (c == '\n') buffer[i++] = ' ';
    else buffer[i++] = c;
  }
  buffer[i] = '\0';
  close(pout[0]);

  // push into lex buffer in reverse
  for (int j = i - 1; j >= 0; j--) {
    myunputc(buffer[j]);
  }
}

\$\{[^ \}\n]*\}([^ \n]*|\$\{[^ \}\n]*\})* {
  std::string val(yytext);
  std::string expanded;

  for (size_t i = 0; i < val.size();) {
    if (val[i] == '$' && i + 1 < val.size() && val[i + 1] == '{') {
      size_t end = val.find('}', i + 2);
      if (end < val.size()) {
        std::string var = val.substr(i + 2, end - (i + 2));
        std::string result;

        if (var == "$") {
          result = std::to_string(getpid());
        } else if (var == "?") {
          result = std::to_string(last_return_code);
        } else if (var == "!") {
          result = std::to_string(last_pid);
        } else if (var == "_") {
          result = last_argument;
        } else if (var == "SHELL") {
          char path[1024];
          realpath("/proc/self/exe", path);
          result = path;
        } else {
          const char *env = getenv(var.c_str());
          result = env ? env : "";
        }
        expanded += result;
        i = end + 1;
      } else {
        expanded += val[i++];
      }
    } else {
      expanded += val[i++];
    }
  }

  yylval.cpp_string = new std::string(expanded);
  return WORD;
}

"source" {
  BEGIN(src);
}

<src>[ \t]*
<src>[^ \t\n][^ \t\n]* {
  FILE * file = fopen(yytext, "r");

  if (!file) {
    perror("fopen");
    BEGIN(INITIAL);
  } else {
    yypush_buffer_state(yy_create_buffer(file, YY_BUF_SIZE));
    BEGIN(INITIAL);
    yyparse();
    yypop_buffer_state();
    fclose(file);
  }
}


~[^ \n\t]* {
  std::string str = std::string(yytext);
  //ls ~
  if (str.size() == 1) {
    std::string home_directory = getenv("HOME");
    yylval.cpp_string = new std::string(home_directory);
  } else {
    //List subdirectory "dir" ls ~george/dir
    if (str[1] == '/') {
      std::string home_directory = getenv("HOME");
      str = home_directory + str.substr(1, -1);
    } else {
      //list home directory ls ~george
      str = std::string("/homes/") + str.substr(1,-1);
    }
    yylval.cpp_string = new std::string(str);
  }
  return WORD;
}

\"[^\n\"]*\" {
  yylval.cpp_string = new std::string(yytext + 1, yyleng - 2);
  return WORD;
}

[^ \t\n|><&]*\\[^ \t\n]* {
  std::string val;
  for (size_t i = 0; i < yyleng; i++) {
    if (yytext[i] == '\\') {
      i++; // skip the first backslash
      if (i < yyleng && yytext[i] != ' ' && yytext[i] != '\t') {
        val += yytext[i]; // append the escaped character except spaces
      }
    } else {
      val += yytext[i];
    }
  }
  yylval.cpp_string = new std::string(val);
  return WORD;
}

[^ \t\n|><&][^ \t\n|><&]* {
  /* Assume that file names have only alpha chars */
  yylval.cpp_string = new std::string(yytext);
  return WORD;
}

%%
