let
  # Params
  bodyParam.description = "body to post";
  bodyParam.name        = "body";
  bodyParam.schema.type = "string";
  hdrsParam.description = "request headers";
  hdrsParam.name        = "headers";
  hdrsParam.schema.type = "object";
  urlParam.description  = "url to post";
  urlParam.name         = "url";
  urlParam.schema.type  = "string";
  # Result
  result.name = "response";
  result.description = "response of your request";
  result.schema.properties.body.description    = "HTTP response body";
  result.schema.properties.body.type           = "string";
  result.schema.properties.code.description    = "HTTP response code";
  result.schema.properties.code.type           = "integer";
  result.schema.properties.headers.description = "HTTP response headers";
  result.schema.properties.headers.type        = "object";
  result.schema.properties.url.description     = "requested URL";
  result.schema.properties.url.type            = "string";
  result.schema.type = "object";
  # Methods
  get.description  = "simple get http";
  get.name         = "/curl/v0/get";
  get.params       = [urlParam hdrsParam];
  get.result       = result;
  post.description = "simple post http";
  post.name        = "/curl/v0/post";
  post.params      = [urlParam hdrsParam];
  post.result      = result;
  batch.description= "multi requests";
  batch.name       = "/curl/v0/batch";
  batch.params     = [ requests ];
  # Batch params
  requests.name    = "requests";
  requests.description = "Array of requests to be performed in batch";
  requests.schema.type = "array";
  requests.schema.items = {
    type = "object";
    required = ["id" "method" "params"];
    properties.id.type     = "string";
    properties.method.type = "string";
    properties.params.type = "object";
    properties.params.required = ["url"];
    properties.params.properties.url.type    = "string";
    properties.params.properties.body.type   = "string";
    properties.params.properties.header.type = "object";
    properties.params.properties.url.description    = urlParam.description;
    properties.params.properties.body.description   = bodyParam.description;
    properties.params.properties.header.description = hdrsParam.description;

  };
in
{
  files.json."/packages/proccurl/PROTOCOLS/STDIO-v1_JSONL-v1_JSON-RPC-v2_OPEN-RPC-v1.json" = {
    id = 1;
    jsonrpc = "2.0";
    result.openrpc = "1.2.1";
    result.methods = [get post batch];
    result.info.version = "1.0.0";
    result.info.title   = "Curl";
  };
}
