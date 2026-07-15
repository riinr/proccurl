let
 model = name: context:
   { spec = "opencode/${name}"; display_name = name; context_window = context;  };
in
{
  files.alias.vix = "nix run github:numtide/llm-agents.nix#vix -- $@";
  files.gitignore.pattern."/.vix/providers.json" = true;
  files.json."/.vix/providers.json" = {
    schema_version = 1;
    providers = [
      {
        id = "opencode";
        display_name = "OpenCode";
        model_prefix = "opencode";
        wire_format = "chat_completions";
        inference.base_url = "https://opencode.ai/zen/v1";
        inference.auth_scheme = "bearer";
        credential_methods = [
          { kind = "api_key"; env_var = "OPENCODE_API_KEY"; keyring = "opencode-api-key"; }
        ];
        models = [
          (model "big-pickle"              200000  )
          (model "claude-fable-5"          1000000 )
          (model "claude-haiku-4-5"        200000  )
          (model "claude-opus-4-1"         200000  )
          (model "claude-opus-4-5"         200000  )
          (model "claude-opus-4-6"         1000000 )
          (model "claude-opus-4-7"         1000000 )
          (model "claude-opus-4-8"         1000000 )
          (model "claude-sonnet-4"         1000000 )
          (model "claude-sonnet-4-5"       1000000 )
          (model "claude-sonnet-4-6"       1000000 )
          (model "claude-sonnet-5"         1000000 )
          (model "deepseek-v4-flash"       1000000 )
          (model "deepseek-v4-flash-free"  200000  )
          (model "deepseek-v4-pro"         1000000 )
          (model "gemini-3-flash"          1048576 )
          (model "gemini-3.1-pro"          1048576 )
          (model "gemini-3.5-flash"        1048576 )
          (model "glm-5"                   204800  )
          (model "glm-5.1"                 204800  )
          (model "glm-5.2"                 1000000 )
          (model "gpt-5"                   400000  )
          (model "gpt-5-codex"             400000  )
          (model "gpt-5-nano"              400000  )
          (model "gpt-5.1"                 400000  )
          (model "gpt-5.1-codex"           400000  )
          (model "gpt-5.1-codex-max"       400000  )
          (model "gpt-5.1-codex-mini"      400000  )
          (model "gpt-5.2"                 400000  )
          (model "gpt-5.2-codex"           400000  )
          (model "gpt-5.3-codex"           400000  )
          (model "gpt-5.3-codex-spark"     128000  )
          (model "gpt-5.4"                 1050000 )
          (model "gpt-5.4-mini"            400000  )
          (model "gpt-5.4-nano"            400000  )
          (model "gpt-5.4-pro"             1050000 )
          (model "gpt-5.5"                 1050000 )
          (model "gpt-5.5-pro"             1050000 )
          (model "gpt-5.6-luna"            1050000 )
          (model "gpt-5.6-sol"             1050000 )
          (model "gpt-5.6-terra"           1050000 )
          (model "grok-4.5"                500000  )
          (model "grok-build-0.1"          256000  )
          (model "hy3-free"                190000  )
          (model "kimi-k2.5"               262144  )
          (model "kimi-k2.6"               262144  )
          (model "kimi-k2.7-code"          262144  )
          (model "mimo-v2.5-free"          200000  )
          (model "minimax-m2.5"            204800  )
          (model "minimax-m2.7"            204800  )
          (model "minimax-m3"              512000  )
          (model "nemotron-3-ultra-free"   1000000 )
          (model "north-mini-code-free"    256000  )
          (model "qwen3.5-plus"            262144  )
          (model "qwen3.6-plus"            262144  )
        ];
      }
    ];
    auth_logins = [ ];
  };

  files.gitignore.pattern."/.vix/settings.json" = true;
  files.json."/.vix/settings.json" = {
    version = 1;
    skills.paths = [ "./.vix/skills" ];
    lsp.nim.command    = [ "nimlangserver" ];
    lsp.nim.extensions = [ ".nim" ];
    mcp_servers = [
      {
        name = "context7";
        command = "context7-mcp";
        args = [ ];
        env= {
          CONTEXT7_API_KEY = "{env:CONTEXT7_API_KEY}";
        };
      }
      {
        name = "hydradb";
        command = "npx";
        args = [ "-y" "@hydradb/mcp@latest" ];
        env= {
          HYDRA_DB_API_KEY = "{env:HYDRA_DB_API_KEY}";
          HYDRA_DB_TENANT_ID = "hugosenari";
        };
      }
      {
        name = "mcpcurl";
        command = "/home/hugosenari/Code/proccurl/mcpcurl";
        args = [ ];
      }
      {
        name = "nimctx";
        command = "nimctx";
        args = [ ];
      }
      {
        name = "nimlang";
        command = "nimlangserver";
        args = [ "--mcp" ];
      }
    ];
  };
}
