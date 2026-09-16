{
  writers,
  python3Packages,
}:

writers.writePython3Bin "pseg-import" {
  libraries = [ python3Packages.websockets ];
  flakeIgnore = [ "E501" ];
} (builtins.readFile ./pseg_import.py)
