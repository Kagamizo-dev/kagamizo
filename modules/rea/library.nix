# modules/rea in the shell's library (../shell): a card on the reverse shelf
# for the module, and the workbench's graphical tools as cards on the Yoga.
{
  shell.apps = {
    reverse-engineering = {
      name = "Reverse engineering";
      category = "reverse";
      kind = "module";
      module = "rea";
      description = "REA and the workbench: the owner's programs and devices mapped into typed catalogs";
    };
    ghidra = {
      name = "Ghidra";
      category = "reverse";
      kind = "native";
      module = "rea";
      command = "ghidra";
      description = "Decompile and annotate binaries of any architecture";
      targets = [ "yoga-c940" ];
    };
    cutter = {
      name = "Cutter";
      category = "reverse";
      kind = "native";
      module = "rea";
      command = "cutter";
      description = "rizin's graphical front end";
      targets = [ "yoga-c940" ];
    };
    imhex = {
      name = "ImHex";
      category = "reverse";
      kind = "native";
      module = "rea";
      command = "imhex";
      description = "A hex editor with patterns for formats and firmware";
      targets = [ "yoga-c940" ];
    };
  };
}
