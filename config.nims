let cosmoPath = getEnv "COSMO_PATH"


when defined cosmopolitan:
  switch "os", "linux"
  switch "cc", "gcc"
  switch "gcc.exe",       cosmoPath & "/bin/cosmocc"
  switch "gcc.linkerexe", cosmoPath & "/bin/cosmocc"
  switch "gcc.options.always", "-static -fno-pie -no-pie "

