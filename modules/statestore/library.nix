# modules/statestore in the shell's library (../shell): part of the base, a row of
# Settings under Infrastructure.
{
  shell.base."statestore" = {
    section = "infrastructure";
    why = "Proton Pass as OpenTofu's state backend";
  };
}
