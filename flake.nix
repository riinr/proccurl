{
  description = "Dev Environment";
  inputs.dsf.url     = "github:cruel-intentions/devshell-files";
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  inputs.dsf.inputs.nixpkgs.follows = "nixpkgs";

  outputs = inputs: inputs.dsf.lib.shell inputs [
    ./.nix/project.nix   # import nix module
    ./.nix/opencode.nix  # import opencode configuration as nix module
    ./.nix/stdio-v1_json-v1_json-rpc-v1-curl-open-rpc.nix
    ./.nix/nimctx.nix
    ./.nix/vix.nix
  ];
}
