#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

#define MAX_BUFFER_LINE 2048
#define MAX_HISTORY 128

extern void tty_raw_mode(void);
extern void tty_reset_mode(void);
// Buffer where line is stored
int line_length;
char line_buffer[MAX_BUFFER_LINE];
int right_length=0;
char right_buffer[MAX_BUFFER_LINE];

// Simple history array
// This history does not change.
// Yours have to be updated.
int history_index = 0;
int history_length = 0;
char * history [MAX_HISTORY];
/*
char * history [] = {
  "ls -al | grep x",
  "ps -e",
  "cat read-line-example.c",
  "vi hello.c",
  "make",
  "ls -al | grep xxx | grep yyy"
};
*/
//int history_length = sizeof(history)/sizeof(char *);

void read_line_print_usage()
{
  char * usage = "\n"
    " ctrl-?       Print usage\n"
    " Left         Move cursor to left\n"
    " Right        Move cursor to right\n"
    " Delete       Deletes character at cursor\n"
    " Backspace    Deletes last character\n"
    " Home         Move to beginning\n"
    " End          Move to end\n"
    " Up           See the previous command\n"
    " Down         Shows the next command\n";

  write(1, usage, strlen(usage));
}

/*
 * Input a line with some basic editing.
 */
void clear_line() {
    write(1, "\33[2K\r", 5); // clear the line and move cursor to start
}

char * read_line() {

  // Set terminal in raw mode
  tty_raw_mode();

  line_length = 0;
  right_length = 0;

  // Read one line until enter is typed
  while (1) {

    // Read one character in raw mode.
    char ch;
    read(0, &ch, 1);

    if (ch>=32) {
      // It is a printable character.

      // Do echo
      write(1,&ch,1);

      // If max number of character reached return.
      if (line_length==MAX_BUFFER_LINE-2) break;

      // add char to buffer.
      line_buffer[line_length]=ch;
      line_length++;
    }
    else if (ch==10 && ch != 127) {
      // <Enter> was typed. Return line
      // Move characters from right buffer to main buffer
      while (right_length > 0) {
        line_buffer[line_length] = right_buffer[right_length - 1];
        right_length--;
        line_length++;
      }
      right_length = 0;
      write(1,&ch,1);
      line_buffer[line_length] = 0;
      break;
    }
    else if (ch == 31) {
      // ctrl-?
      read_line_print_usage();
      line_buffer[0]=0;
      break;
    }
    else if (ch == 8 || ch == 127) {
      // <backspace> was typed. Remove previous character read
      // ctrl-H
      if (line_length == 0 && right_length == 0) {
        continue;
      }
      if (right_length == 0) {
        // Cursor at end of line
        // Move back
        ch = 8;
        write(1,&ch,1);

        // Write a space to erase the last character read
        ch = ' ';
        write(1,&ch,1);

        // Go back one character
        ch = 8;
        write(1,&ch,1);

        // Remove one character from buffer
        line_length--;
      } else {
        // Cursor in middle of line
        ch = 8;
        write(1, &ch, 1);

        // Remove last char of line_buffer
        line_length--;
        // First, print all characters in right_buffer to redraw
        for (int i = right_length - 1; i >= 0; i--) {
          write(1, &right_buffer[i], 1);
        }

        // erase last character
        ch = ' ';
        write(1, &ch, 1);

        // Move cursor back to original position
        for (int i = 0; i <= right_length; i++) {
          ch = 8;
          write(1, &ch, 1);
        }
      }
    }
    else if (ch==27) {
    // Escape sequence. Read two chars more
    //
    // HINT: Use the program "keyboard-example" to
    // see the ascii code for the different chars typed.
    //
    char ch1;
    char ch2;
    read(0, &ch1, 1);
    read(0, &ch2, 1);

    if (ch1 == 91 && ch2 == 68) {
      // Left arrow
      if (line_length > 0) {  // Only if cursor not at start
        ch = 8;
        write(1, &ch, 1);

        right_buffer[0] = line_buffer[line_length - 1];
        right_length++;
        line_length--;
      }
    }
    else if (ch1 == 91 && ch2 == 67) {
      // Right arrow
      if (right_length > 0) {  // Only if cursor not at end
        write(1, "\033[1C" ,5);
        line_buffer[line_length] = right_buffer[right_length-1];
        line_length++;
        right_length--;
      }
    }
   }
   else if (ch == 1) {
     // ctrl-A
     while(line_length > 0){
       char c = 8;
       write(1, &c, 1);
       right_buffer[right_length] = line_buffer[line_length - 1];
       right_length++;
       line_length--;
     }
   }
   else if (ch == 5) {
     // ctrl-E
     while(right_length > 0){
       line_buffer[line_length] = right_buffer[right_length-1];
       right_length--;
       line_length++;
       write(1,"\033[1C",5);
     }
  }
  else if (ch == 4) {
    // ctrl-D
    if (right_length == 0) {
      continue;
    }
    for (int i = right_length - 2; i>=0; i--) {
      char c = right_buffer[i];
      write(1, &c, 1);
    }
    ch = ' ';
    write(1, &ch, 1);
    // Erase last char
    for (int i = 0; i<right_length; i++) {
      char c = 8;
      write(1, &c, 1); // Move cursor back
    }
    right_length--;
  }

  }

  // Add eol and null char at the end of string
  line_buffer[line_length]=10;
  line_length++;
  line_buffer[line_length]=0;
  tty_reset_mode();
  return line_buffer;
}