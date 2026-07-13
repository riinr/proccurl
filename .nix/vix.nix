{
  files.gitignore.pattern."vix.json" = true;
  files.json."/vix.json" = {
    "$schema" = "https://vix.ai/config.json";
    skills.paths = [ "./.vix/skills" ];
    lsp.nim.command    = [ "nimlangserver" ];
    lsp.nim.extensions = [ ".nim" ];
    mcp.hydradb.enabled = true;
    mcp.hydradb.type    = "local";
    mcp.hydradb.command = [ "npx" "-y" "@hydradb/mcp@latest" ];
    mcp.hydradb.environment = {
      HYDRA_DB_API_KEY = "{env:HYDRA_DB_API_KEY}";
      HYDRA_DB_TENANT_ID = "hugosenari";
    };
    mcp.context7.enabled = true;
    mcp.context7.type    = "local";
    mcp.context7.command = [ "context7-mcp" ];
    mcp.context7.environment.CONTEXT7_API_KEY = "{env:CONTEXT7_API_KEY}";
    mcp.nimctx.enabled = true;
    mcp.nimctx.type    = "local";
    mcp.nimctx.command = [ "nimctx" ];
    mcp.nimlang.enabled = true;
    mcp.nimlang.type    = "local";
    mcp.nimlang.command = [ "nimlangserver"  "--mcp"];
    mcp.mcpcurl.enabled = true;
    mcp.mcpcurl.type    = "local";
    mcp.mcpcurl.command = [ "/home/hugosenari/Code/proccurl/mcpcurl" ];
  };
}