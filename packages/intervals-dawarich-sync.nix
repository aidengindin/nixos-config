{
  writers,
  python3Packages,
}:

writers.writePython3Bin "intervals-dawarich-sync" {
  libraries = [ python3Packages.requests ];
  # The script keeps a few long-but-readable lines; nothing else is waived.
  flakeIgnore = [ "E501" ];
} (builtins.readFile ./intervals_dawarich_sync.py)
