let
 openCodeModel = name: context:
   { spec = "opencode/${name}"; display_name = name; context_window = context;  };
 nvidiaModel   = title: name: context:
   { spec = name; display_name = title; context_window = context;  };
in
{
  files.gitignore.pattern."/.vix/" = true;
  files.alias.vix = "nix run github:numtide/llm-agents.nix#vix -- $@";
  files.json."/.vix/settings.json" = {
    version = 1;
    allowed_directories= [ "." "~/.nimble" "/nix/store" ];
    deny_list.paths    = [ ".envrc.private" ];
    skills.paths       = [ ".vix/skills/*/SKILL.md" ".opencode/nim-skills/*/SKILL.md" ];
    languages = [
      { 
        name        = "nim";
	extensions  = [".nim" ".nimble"];
	lsp.command = "nimlangserver";
      }
    ];
    mcp_servers = [
      {
        name    = "mcpcurl";
        command = "/home/hugosenari/Code/proccurl/bin/mcpcurl";
      }
      {
        name    = "webdrivermcp";
        command = "/home/hugosenari/Code/proccurl/bin/webdrivermcp";
      }
      {
        name    = "nimctx";
        command = "nimctx";
      }
      {
        name    = "nimlang";
        command = "nimlangserver";
        args    = [ "--mcp" ];
      }
    ];
    workflows = [];
  };
  files.json."/.vix/providers.json" = {
    schema_version = 1;
    providers = [
      {
        id           = "nvidia";
        display_name = "NVidia";
        model_prefix = "nvidia";
        wire_format  = "chat_completions";
        inference.base_url    = "https://integrate.api.nvidia.com/v1";
        inference.auth_scheme = "bearer";
        credential_methods = [{ kind = "api_key"; env_var = "NVIDIA___API_KEY"; keyring = "opencode-api-key"; }];
        models = [
	  (nvidiaModel "Laguna"   "poolside/laguna-xs-2.1"             8192)
	  (nvidiaModel "Minima"   "minimaxai/minimax-m3"               8192)
	  (nvidiaModel "Nemotron" "nvidia/nemotron-3-ultra-550b-a55b" 16384)
	  (nvidiaModel "Step"     "stepfun-ai/step-3.7-flash"         16384)
	  (nvidiaModel "Kimi"     "moonshotai/kimi-k2.6"              16384)
	  (nvidiaModel "Mistral"  "mistralai/mistral-medium-3.5-128b" 16384)
	  (nvidiaModel "Deepseek" "deepseek-ai/deepseek-v4-flash"     16384)
	  (nvidiaModel "Gemma"    "google/gemma-4-31b-it"             16384)
	  (nvidiaModel "GLM"      "z-ai/glm-5.2"                      16384)
	];
      }
      {
        id           = "google";
	display_name = "Google";
	model_prefix = "google";
	wire_format  = "chat_completions";
	inference.base_url = "https://generativelanguage.googleapis.com/v1beta/interactions";
	inference.auth_scheme = "x-api-key";
	inference.auth_header = "x-goog-api-key";
	credential_methods = [{ kind = "api_key"; env_var = "GEMINI___API_KEY"; keyring = "opencode-api-key";  }];
        models = [{ spec = "gemini-3.5-flash"; display_name = "Gemini3"; context_window = 200000; }];
      }
      {
        id           = "llmgateway";
	display_name = "LLMGateway";
	model_prefix = "llmgatewsay";
	wire_format  = "messages";
	inference.base_url    = "https://api.llmgateway.io/v1";
	inference.auth_scheme = "bearer";
	credential_methods = [{ kind = "api_key"; env_var = "LLMGTWAY_API_KEY"; keyring = "opencode-api-key";  }];
        models = [{ spec = "anthropic/claude-haiku-4-5-free"; display_name = "Haiku"; context_window = 200000; }];
      }
      {
        id           = "opencode";
        display_name = "OpenCode";
        model_prefix = "opencode";
        wire_format  = "chat_completions";
        inference.base_url    = "https://opencode.ai/zen/v1";
        inference.auth_scheme = "bearer";
        credential_methods = [{ kind = "api_key"; env_var = "OPENCODE_API_KEY"; keyring = "opencode-api-key"; }];
        models = [
          (openCodeModel "big-pickle"              200000  )
          (openCodeModel "claude-fable-5"          1000000 )
          (openCodeModel "claude-haiku-4-5"        200000  )
          (openCodeModel "claude-opus-4-1"         200000  )
          (openCodeModel "claude-opus-4-5"         200000  )
          (openCodeModel "claude-opus-4-6"         1000000 )
          (openCodeModel "claude-opus-4-7"         1000000 )
          (openCodeModel "claude-opus-4-8"         1000000 )
          (openCodeModel "claude-sonnet-4"         1000000 )
          (openCodeModel "claude-sonnet-4-5"       1000000 )
          (openCodeModel "claude-sonnet-4-6"       1000000 )
          (openCodeModel "claude-sonnet-5"         1000000 )
          (openCodeModel "deepseek-v4-flash"       1000000 )
          (openCodeModel "deepseek-v4-flash-free"  200000  )
          (openCodeModel "deepseek-v4-pro"         1000000 )
          (openCodeModel "gemini-3-flash"          1048576 )
          (openCodeModel "gemini-3.1-pro"          1048576 )
          (openCodeModel "gemini-3.5-flash"        1048576 )
          (openCodeModel "glm-5"                   204800  )
          (openCodeModel "glm-5.1"                 204800  )
          (openCodeModel "glm-5.2"                 1000000 )
          (openCodeModel "gpt-5"                   400000  )
          (openCodeModel "gpt-5-codex"             400000  )
          (openCodeModel "gpt-5-nano"              400000  )
          (openCodeModel "gpt-5.1"                 400000  )
          (openCodeModel "gpt-5.1-codex"           400000  )
          (openCodeModel "gpt-5.1-codex-max"       400000  )
          (openCodeModel "gpt-5.1-codex-mini"      400000  )
          (openCodeModel "gpt-5.2"                 400000  )
          (openCodeModel "gpt-5.2-codex"           400000  )
          (openCodeModel "gpt-5.3-codex"           400000  )
          (openCodeModel "gpt-5.3-codex-spark"     128000  )
          (openCodeModel "gpt-5.4"                 1050000 )
          (openCodeModel "gpt-5.4-mini"            400000  )
          (openCodeModel "gpt-5.4-nano"            400000  )
          (openCodeModel "gpt-5.4-pro"             1050000 )
          (openCodeModel "gpt-5.5"                 1050000 )
          (openCodeModel "gpt-5.5-pro"             1050000 )
          (openCodeModel "gpt-5.6-luna"            1050000 )
          (openCodeModel "gpt-5.6-sol"             1050000 )
          (openCodeModel "gpt-5.6-terra"           1050000 )
          (openCodeModel "grok-4.5"                500000  )
          (openCodeModel "grok-build-0.1"          256000  )
          (openCodeModel "hy3-free"                190000  )
          (openCodeModel "kimi-k2.5"               262144  )
          (openCodeModel "kimi-k2.6"               262144  )
          (openCodeModel "kimi-k2.7-code"          262144  )
          (openCodeModel "mimo-v2.5-free"          200000  )
          (openCodeModel "minimax-m2.5"            204800  )
          (openCodeModel "minimax-m2.7"            204800  )
          (openCodeModel "minimax-m3"              512000  )
          (openCodeModel "nemotron-3-ultra-free"   1000000 )
          (openCodeModel "north-mini-code-free"    256000  )
          (openCodeModel "qwen3.5-plus"            262144  )
          (openCodeModel "qwen3.6-plus"            262144  )
        ];
      }
    ];
    auth_logins = [ ];
  };


  files.text."/.vix/skills/vix-help/SKILL.MD" = ''
  ---
  name: vix-help
  description: Answer questions about vix interface, keyboard shortcuts, configuration, agents, providers, jobs, etc  
  ---

  Grep inside in ./.vix/docs/*.md for $ARGUMENTS
  If any file match try to load it to respond user question
  If no file match read all files in ./.vix/docs/*.md and use them to repond user question
  '';
}
