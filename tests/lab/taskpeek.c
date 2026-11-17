/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026 AmiCradle Team
 * From DalsinAI/amigafreeciv platforms/amigaos3/tests/task_peek.c.
 *
 * TaskPeek: what a stuck program is waiting for.
 *
 *   TaskPeek [NAME [LONGWORDS]]
 *
 * Lists every task (name, state, signals waited for and received). For each
 * process whose command or task name contains NAME it also prints its
 * program's hunks (from the CLI's cli_Module or pr_SegList) and LONGWORDS
 * (default 192) longwords from its saved stack pointer, marking each one
 * that points into a hunk as "hunk N + offset": with the unstripped
 * executable's symbol table those are the calls it is waiting inside.
 * Everything is copied under Forbid() and printed after Permit().
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <exec/execbase.h>
#include <exec/tasks.h>
#include <dos/dosextens.h>
#include <proto/exec.h>

extern struct ExecBase *SysBase;

#define MAX_TASKS 96
#define MAX_HUNKS 16
#define MAX_WORDS 512

struct seen {
  char name[40];
  char command[40];
  UBYTE state;
  ULONG sigwait, sigrecvd, sigalloc;
  APTR sp, splower, spupper;
  int nhunks;
  ULONG hunk_start[MAX_HUNKS], hunk_size[MAX_HUNKS];
  int nwords;
  ULONG words[MAX_WORDS];
};

static struct seen seen[MAX_TASKS];
static int nseen;
static const char *want;
static int want_words = 192;

static void copy_bstr(char *to, size_t size, BSTR b)
{
  const UBYTE *s = BADDR(b);
  size_t n;

  to[0] = '\0';
  if (s == NULL) {
    return;
  }
  n = s[0] < size - 1 ? s[0] : size - 1;
  memcpy(to, s + 1, n);
  to[n] = '\0';
}

static void take(struct Task *t)
{
  struct seen *s;

  if (nseen >= MAX_TASKS) {
    return;
  }
  s = &seen[nseen++];
  memset(s, 0, sizeof(*s));
  strncpy(s->name, t->tc_Node.ln_Name ? t->tc_Node.ln_Name : "?", sizeof(s->name) - 1);
  s->state = t->tc_State;
  s->sigwait = t->tc_SigWait;
  s->sigrecvd = t->tc_SigRecvd;
  s->sigalloc = t->tc_SigAlloc;
  s->sp = t->tc_SPReg;
  s->splower = t->tc_SPLower;
  s->spupper = t->tc_SPUpper;
  if (t->tc_Node.ln_Type == NT_PROCESS) {
    struct Process *p = (struct Process *) t;
    struct CommandLineInterface *cli = BADDR(p->pr_CLI);
    BPTR seg = 0;

    if (cli != NULL) {
      copy_bstr(s->command, sizeof(s->command), cli->cli_CommandName);
      seg = cli->cli_Module;
    }
    if (seg == 0 && p->pr_SegList != 0) {
      BPTR *array = BADDR(p->pr_SegList);

      seg = array[3];         /* the program's own segment list */
    }
    if (want != NULL && (strstr(s->name, want) || strstr(s->command, want))) {
      ULONG *w = (ULONG *) s->sp, *top = (ULONG *) s->spupper;

      while (seg != 0 && s->nhunks < MAX_HUNKS) {
        ULONG *h = BADDR(seg);

        s->hunk_start[s->nhunks] = (ULONG) (h + 1);
        s->hunk_size[s->nhunks] = h[-1] - 8;
        s->nhunks++;
        seg = (BPTR) h[0];
      }
      if (t != SysBase->ThisTask) {
        while (w < top && s->nwords < want_words) {
          s->words[s->nwords++] = *w++;
        }
      }
    }
  }
}

static void take_list(struct List *l)
{
  struct Node *n;

  for (n = l->lh_Head; n->ln_Succ != NULL; n = n->ln_Succ) {
    take((struct Task *) n);
  }
}

static const char *state_name(UBYTE s)
{
  switch (s) {
  case TS_RUN: return "run";
  case TS_READY: return "ready";
  case TS_WAIT: return "wait";
  case TS_EXCEPT: return "except";
  case TS_REMOVED: return "removed";
  default: return "?";
  }
}

int main(int argc, char **argv)
{
  int i, j, k;

  if (argc > 1) {
    want = argv[1];
  }
  if (argc > 2) {
    want_words = atoi(argv[2]);
    if (want_words < 1 || want_words > MAX_WORDS) {
      want_words = MAX_WORDS;
    }
  }
  Forbid();
  take(SysBase->ThisTask);
  take_list(&SysBase->TaskReady);
  take_list(&SysBase->TaskWait);
  Permit();

  for (i = 0; i < nseen; i++) {
    struct seen *s = &seen[i];

    printf("%-7s wait %08lx recvd %08lx alloc %08lx  %s%s%s\n",
           state_name(s->state), (unsigned long) s->sigwait,
           (unsigned long) s->sigrecvd, (unsigned long) s->sigalloc, s->name,
           s->command[0] ? " / " : "", s->command);
  }
  for (i = 0; i < nseen; i++) {
    struct seen *s = &seen[i];

    if (s->nhunks == 0 && s->nwords == 0) {
      continue;
    }
    printf("\n== %s / %s: %s, waits for %08lx, sp %08lx (stack %08lx-%08lx)\n",
           s->name, s->command, state_name(s->state), (unsigned long) s->sigwait,
           (unsigned long) s->sp, (unsigned long) s->splower,
           (unsigned long) s->spupper);
    for (j = 0; j < s->nhunks; j++) {
      printf("hunk %d at %08lx, %lu bytes\n", j, (unsigned long) s->hunk_start[j],
             (unsigned long) s->hunk_size[j]);
    }
    for (k = 0; k < s->nwords; k++) {
      ULONG v = s->words[k];

      printf("sp+%03x %08lx", k * 4, (unsigned long) v);
      for (j = 0; j < s->nhunks; j++) {
        if (v >= s->hunk_start[j] && v < s->hunk_start[j] + s->hunk_size[j]) {
          printf("  hunk %d + %lx", j, (unsigned long) (v - s->hunk_start[j]));
        }
      }
      if (v >= 0x00f80000 && v < 0x01000000) {
        printf("  ROM");
      }
      printf("\n");
    }
  }
  return 0;
}
