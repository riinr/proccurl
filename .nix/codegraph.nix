{
  files.gitignore.pattern."codegraph.json" = true;
  files.alias.codegraph = "nix run github:numtide/llm-agents.nix#codegraph -- $@";
  files.json."/codegraph.json" = {
    include = [".nix"];
  };
}
