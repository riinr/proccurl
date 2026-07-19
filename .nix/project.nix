{ pkgs, inputs, ...}:
{
  # Name your shell environment
  devshell.name = "proccurl";

  # create .gitignore
  files.gitignore.enable = true;
  # copy contents from https://github.com/github/gitignore
  # to our .gitignore
  files.gitignore.template."Global/Archives" = true;
  files.gitignore.template."Global/Backup"   = true;
  files.gitignore.template."Global/Diff"     = true;
  files.gitignore.pattern."*\n!/**/\n!*.*"   = true;
  files.gitignore.pattern.".*"               = true;
  files.gitignore.pattern."!.nix/*"          = true;

  # install a packages
  packages = [
    pkgs.curlFull.out
    pkgs.zlib
    pkgs.nim
    pkgs.nimble
    pkgs.nimlangserver
    pkgs.binutils
    pkgs.ripgrep
    pkgs.gcc
    pkgs.context7-mcp
    pkgs.geckodriver
  ];

  # configure direnv .envrc file
  files.direnv.enable = true;

  files.alias.find-executables = ''
    # Find executable files
    find . -type f -executable \
      -not -name '*.sample' \
      -not -name '*.sh' \
      -not -path '*/.*' \
      $@
  '';

  files.alias.docs = ''
    # Compiles all docs
    find $PRJ_ROOT/src/proccurl/ -maxdepth 1 -name '*.nim' \
     -execdir nim doc {} \;
  '';

  files.alias.benchc = ''
    # Compiles all benchmarks
    find $PRJ_ROOT/bench -maxdepth 1 -name '*.nim' \
     -execdir nim c \
       --mm:arc \
       --passC:"-march=native" \
       -d:boring.benchruns:''${1:-50} \
       -d:boring.benchslots:''${2:-5} \
       -d:release  \
       -d:danger   \
       --opt:speed \
       {} \;
  '';

  files.alias.benchr = ''
    # Run all benchmarks
    for i in $(find $PRJ_ROOT/bench -maxdepth 1 -type f -executable); do
      echo $i
      $i
    done
  '';

  files.alias.ipcs = ''
    # Compile and RUN IPC main command as Server
    rm -rf /tmp/ipc-*.mmap
    nim c -o:/tmp/proccurl-ipc-main $PRJ_ROOT/src/proccurl/ipc.nim && \
      /tmp/proccurl-ipc-main 08x32 08x32
  '';

  files.alias.ipcc = ''
    # RUN IPC main command as Client (server must be running)
    /tmp/proccurl-ipc-main 08x32 08x32 /tmp/ipc-*.mmap
  '';

  files.alias.build = ''
    # BUILD all binaries
    nim c --threads:on -o:bin/proccurl src/proccurl.nim
    nim c --threads:on -o:bin/mcpcurl src/mcpcurl.nim
  '';

  files.alias.build-mcpcurl = ''
    # BUILD mcpcurl only
    nim c --threads:on -o:bin/mcpcurl src/mcpcurl.nim
  '';

  files.alias.build-proccurl = ''
    # BUILD proccurl only
    nim c --threads:on -o:bin/proccurl src/proccurl.nim
  '';

  env = [
    { name = "LD_LIBRARY_PATH"; prefix = "${pkgs.curlFull.out}/lib:${pkgs.cosmopolitan}/lib";}
    { name = "LDFLAGS";         prefix = "-L${pkgs.zlib}/lib";}
    { name = "NIX_LDFLAGS";     value = "-L${pkgs.zlib}/lib";}
    #{ name = "PKG_CONFIG_PATH"; prefix = "${pkgs.mimalloc.dev}/lib/pkgconfig";}
    { name = "COSMO_PATH";      prefix = "${pkgs.cosmocc}";}
  ];
}
