///| Render report as JSON string.
pub fn Report::to_json(self : Report) -> String {
  let sum = self.summarize()
  let get_n = (k : String) => match sum.get(k) {
    Some(v) => v
    None => 0
  }
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
      "timing_ms": Json::number(r.timing_ms.to_double()),
    })
  }))
  Json::object({
    "server_cmd": Json::string(self.server_cmd),
    "protocol_version": Json::string(self.protocol_version),
    "timestamp": Json::string(self.timestamp),
    "results": arr,
    "summary": Json::object({
      "pass": Json::number(get_n("pass").to_double()),
      "fail": Json::number(get_n("fail").to_double()),
      "skip": Json::number(get_n("skip").to_double()),
      "warn": Json::number(get_n("warn").to_double()),
    }),
    "total_timing_ms": Json::number(self.total_timing_ms.to_double()),
    "avg_timing_ms": Json::number(self.avg_timing_ms.to_double()),
  }).stringify()
}

///| Render report as Markdown string.
pub fn Report::to_markdown(self : Report) -> String {
  let sb = StringBuilder()
  ignore(sb.write_string("# mcpconftest report\n\n"))
  ignore(sb.write_string("Server: `\{self.server_cmd}`\n\n"))
  ignore(sb.write_string("Protocol: \{self.protocol_version}\n\n"))
  ignore(sb.write_string("Timestamp: \{self.timestamp}\n\n"))
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
  ignore(sb.write_string("## Summary\n\n"))
  ignore(sb.write_string("| Metric | Count |\n"))
  ignore(sb.write_string("|---|---|\n"))
  ignore(sb.write_string("| Pass | \{p} |\n"))
  ignore(sb.write_string("| Fail | \{f} |\n"))
  ignore(sb.write_string("| Skip | \{s} |\n"))
  ignore(sb.write_string("| Warn | \{w} |\n"))
  ignore(sb.write_string("| Total timing | \{self.total_timing_ms}ms |\n"))
  ignore(sb.write_string("| Avg per check | \{self.avg_timing_ms}ms |\n\n"))
  ignore(sb.write_string("## Details\n\n"))
  for r in self.results {
    let icon = match r.severity {
      Pass => "✅"
      Fail => "❌"
      Skip => "⏭️"
      Warn => "⚠️"
    }
    ignore(sb.write_string("### \{icon} \{r.name} (\{r.timing_ms}ms)\n\n"))
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
    total_timing_ms: 0,
    avg_timing_ms: 0,
  }
  r.summary = r.summarize()
  r
}

///| Escape HTML special characters.
fn html_escape(s : String) -> String {
  s.replace(old="&", new="&amp;")
  .replace(old="<", new="&lt;")
  .replace(old=">", new="&gt;")
  .replace(old="\"", new="&quot;")
}

///| Render report as a standalone HTML page.
pub fn Report::to_html(self : Report) -> String {
  let sum = self.summarize()
  let get_n = (k : String) => match sum.get(k) {
    Some(v) => v
    None => 0
  }
  let sb = StringBuilder()
  ignore(sb.write_string("<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n"))
  ignore(sb.write_string("<meta charset=\"utf-8\">\n"))
  ignore(sb.write_string("<title>mcpconftest report — \{html_escape(self.server_cmd)}</title>\n"))
  ignore(sb.write_string("<style>\n"))
  ignore(sb.write_string("body{font-family:system-ui,sans-serif;margin:2rem;color:#1a1a2e}\n"))
  ignore(sb.write_string("h1{border-bottom:2px solid #16213e}table{border-collapse:collapse;margin:1rem 0}\n"))
  ignore(sb.write_string("td,th{border:1px solid #ccc;padding:.4rem .8rem;text-align:left}\n"))
  ignore(sb.write_string(".pass{color:#0a7d32}.fail{color:#c0392b;font-weight:bold}.skip{color:#888}.warn{color:#b8860b}\n"))
  ignore(sb.write_string("details{margin:.5rem 0}summary{cursor:pointer}\n"))
  ignore(sb.write_string("pre{background:#f4f4f8;padding:.6rem;overflow-x:auto}\n"))
  ignore(sb.write_string("</style>\n</head>\n<body>\n"))
  ignore(sb.write_string("<h1>mcpconftest report</h1>\n"))
  ignore(sb.write_string("<p>Server: <code>\{html_escape(self.server_cmd)}</code><br>\n"))
  ignore(sb.write_string("Protocol: \{html_escape(self.protocol_version)}<br>\n"))
  ignore(sb.write_string("Timestamp: \{html_escape(self.timestamp)}</p>\n"))
  ignore(sb.write_string("<h2>Summary</h2>\n<table><tr><th>Pass</th><th>Fail</th><th>Skip</th><th>Warn</th></tr>\n"))
  ignore(sb.write_string("<tr><td>\{get_n("pass")}</td><td>\{get_n("fail")}</td><td>\{get_n("skip")}</td><td>\{get_n("warn")}</td></tr></table>\n"))
  ignore(sb.write_string("<h2>Details</h2>\n"))
  for r in self.results {
    let cls = match r.severity {
      Pass => "pass"
      Fail => "fail"
      Skip => "skip"
      Warn => "warn"
    }
    let icon = match r.severity {
      Pass => "&#9989;"
      Fail => "&#10060;"
      Skip => "&#9209;&#65039;"
      Warn => "&#9888;&#65039;"
    }
    ignore(sb.write_string("<details><summary><span class=\"\{cls}\">\{icon} \{html_escape(r.name)}</span> — \{html_escape(r.message)}</summary>\n"))
    match r.evidence {
      Some(e) if e.length() > 0 =>
        ignore(sb.write_string("<pre>\{html_escape(e)}</pre>\n"))
      _ => ()
    }
    ignore(sb.write_string("</details>\n"))
  }
  ignore(sb.write_string("</body>\n</html>\n"))
  sb.to_string()
}

///| Render report as JUnit XML (CI-native test results).
pub fn Report::to_junit(self : Report) -> String {
  let sum = self.summarize()
  let get_n = (k : String) => match sum.get(k) {
    Some(v) => v
    None => 0
  }
  let sb = StringBuilder()
  let total = self.results.length()
  let failures = get_n("fail")
  ignore(sb.write_string("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"))
  ignore(sb.write_string("<testsuites name=\"mcpconftest\" tests=\"\{total}\" failures=\"\{failures}\">\n"))
  ignore(sb.write_string("<testsuite name=\"mcpconftest.\{html_escape(self.server_cmd)}\" tests=\"\{total}\" failures=\"\{failures}\">\n"))
  for r in self.results {
    let sev_tag = match r.severity {
      Pass => ""
      Fail => "failure"
      Skip => "skipped"
      Warn => "skipped"
    }
    if sev_tag == "" {
      ignore(sb.write_string("<testcase name=\"\{html_escape(r.name)}\" classname=\"mcpconftest\"/>\n"))
    } else if sev_tag == "skipped" {
      ignore(sb.write_string("<testcase name=\"\{html_escape(r.name)}\" classname=\"mcpconftest\"><skipped/>\n"))
      ignore(sb.write_string("</testcase>\n"))
    } else {
      let msg = match r.evidence {
        Some(e) if e.length() > 0 => "\{r.message} | evidence: \{e}"
        _ => r.message
      }
      ignore(sb.write_string("<testcase name=\"\{html_escape(r.name)}\" classname=\"mcpconftest\">\n"))
      ignore(sb.write_string("<failure message=\"\{html_escape(r.message)}\">\{html_escape(msg)}</failure>\n"))
      ignore(sb.write_string("</testcase>\n"))
    }
  }
  ignore(sb.write_string("</testsuite>\n</testsuites>\n"))
  sb.to_string()
}
pub fn Report::write_to_dir(self : Report, dir : String, with_junit : Bool) -> Result[Unit, String] {
  if fs_mkdir_p(dir) != 0 {
    return Err("mkdir failed: \{dir}")
  }
  if fs_write_file("\{dir}/report.json", self.to_json()) != 0 {
    return Err("write failed: \{dir}/report.json")
  }
  if fs_write_file("\{dir}/report.md", self.to_markdown()) != 0 {
    return Err("write failed: \{dir}/report.md")
  }
  if fs_write_file("\{dir}/report.html", self.to_html()) != 0 {
    return Err("write failed: \{dir}/report.html")
  }
  if with_junit {
    if fs_write_file("\{dir}/report-junit.xml", self.to_junit()) != 0 {
      return Err("write failed: \{dir}/report-junit.xml")
    }
  }
  Ok(())
}
