{ ... }:
let
  globalVars = {
    ports = {
      grafana = 10001;
      prometheus = 10002;
      prometheusNodeExporter = 10003;
      loki = 10004;
      promtail = 10005;
    };
  };
in
{
  _module.args = { inherit globalVars; };
}
