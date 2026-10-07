///| Render report as JSON string.
pub fn Report::to_json(self : Report) -> String {
  let arr = Json::array(self.results.map(fn(r) {
    let sev = match r.severity {
      Pass => Json::string("pass")
      Fail => Json::string("fail")
      Skip => Json::string("skip")
      Warn => Json::string("warn")
    }
    let ev = match r.evidence {
      Some(e) => Json::string(e)
      None => Json::string("")
    }
    Json::object({
      "name": Json::string(r.name),
      "severity": sev,
      "message": Json::string(r.message),
      "evidence": ev,
    })
  }))
  Json::object({
    "server_cmd": Json::string(self.server_cmd),
    "protocol_version": Json::string(self.protocol_version),
    "timestamp": Json::string(self.timestamp),
    "results": arr,
    "summary": Json::object(Map([])),
  }).stringify()
}

///| Render report as Markdown string.
pub fn Report::to_markdown(self : Report) -> String {
  let sb = StringBuilder()
  ignore(sb.write_string("# mcpconftest report\n\n"))
  ignore(sb.write_string("Server: `\{self.server_cmd}`\n\n"))
  ignore(sb.write_string("Protocol: \{self.protocol_version}\n\n"))
  ignore(sb.write_string("Timestamp: \{self.timestamp}\n\n"))
  ignore(sb.write_string("## Summary\n\n"))
  let p = match self.summary.get("pass") {
    Some(v) => v
    None => 0
  }
  let f = match self.summary.get("fail") {
    Some(v) => v
    None => 0
  }
  let s = match self.summary.get("skip") {
    Some(v) => v
    None => 0
  }
  let w = match self.summary.get("warn") {
    Some(v) => v
    None => 0
  }
  ignore(sb.write_string("| Metric | Count |\n"))
  ignore(sb.write_string("|---|---|\n"))
  ignore(sb.write_string("| Pass | \{p} |\n"))
  ignore(sb.write_string("| Fail | \{f} |\n"))
  ignore(sb.write_string("| Skip | \{s} |\n"))
  ignore(sb.write_string("| Warn | \{w} |\n\n"))
  ignore(sb.write_string("## Details\n\n"))
  for r in self.results {
    let icon = match r.severity {
      Pass => "✅"
      Fail => "❌"
      Skip => "⏭️"
      Warn => "⚠️"
    }
    ignore(sb.write_string("### \{icon} \{r.name}\n\n"))
    ignore(sb.write_string("\{r.message}\n\n"))
    match r.evidence {
      Some(e) if e.length() > 0 => ignore(sb.write_string("```json\n\{e}\n```\n\n"))
      _ => ()
    }
  }
  sb.to_string()
}

///| Aggregate all check results into a full report.
pub fn build_report(
  results : Array[CheckResult],
  cmd : String,
  ver : String,
  ts : String
) -> Report {
  let r = {
    server_cmd: cmd,
    protocol_version: ver,
    results,
    summary: Map([]),
    timestamp: ts,
  }
  r.summary = r.summarize()
  r
}
