# HuyUNIX Shell

A **POSIX-compliant UNIX shell** implemented in **C/C++**, supporting pipelines, subshells, and interactive command input. Built with **Flex** and **Bison**, it executes commands using low-level UNIX system calls.

---

## Overview

HuyUNIX Shell is designed to emulate a real UNIX shell. It supports executing built-in and external commands, pipelines (`|`) and subshells, interactive input with command history and tab completion, robust parsing using Flex and Bison, and signal handling (`Ctrl-C`, `Ctrl-D`) with low-level terminal I/O. The shell has been validated with **over 100 automated test cases**

---

## Features

- **Command Execution:** Built-in and external commands, pipelines, subshells  
- **Parsing:** Flex/Bison lexer and parser, Abstract Syntax Tree (AST)  
- **Interactive Shell:** Command history, tab completion, signal handling, terminal management  

---



