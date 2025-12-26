{ ... }:
{
  imports = [ ../../services ];

  agindin.services = {
    postgres.enable = true;

    blocky.enable = true;
  };
}

