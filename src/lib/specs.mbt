///| Spec-driven check catalog (L1: spec is the single source of truth).

///| Reads specs/manifest.json from the current working directory and renders

///| the check category list. Falls back to a static catalog when the manifest

///|
/// is absent (e.g. running from a release bundle without the repo tree).
const SPEC_MANIFEST_PATH : String = "specs/manifest.json"

///|
priv struct SpecEntry {
  check_id : String
  category : String
  title : String
  fingerprint : String
}

///|
/// Load spec manifest entries; returns [] when unavailable.
fn load_specs() -> Array[SpecEntry] {
  let raw = spec_read_file(SPEC_MANIFEST_PATH)
  if raw.length() == 0 {
    return []
  }
  let j = @json.parse(raw) catch { _ => Json::null() }
  let entries : Array[SpecEntry] = []
  match j {
    Json::Array(arr) =>
      for item in arr {
        match item {
          Json::Object(o) => {
            let check_id = match o.get("check_id") {
              Some(Json::String(s)) => s
              _ => continue
            }
            let category = match o.get("category") {
              Some(Json::String(s)) => s
              _ => ""
            }
            let title = match o.get("title") {
              Some(Json::String(s)) => s
              _ => ""
            }
            let fingerprint = match o.get("fingerprint") {
              Some(Json::String(s)) => s
              _ => ""
            }
            entries.push({ check_id, category, title, fingerprint, })
          }
          _ => ()
        }
      }
    _ => ()
  }
  entries
}

///| Fallback title resolution: read the per-check spec.json for its title

///|
/// when the manifest entry omits it. Path = specs/<category>/<leaf>/spec.json.
fn resolve_title(e : SpecEntry) -> String {
  if e.title.length() > 0 {
    return e.title
  }
  if e.category.length() == 0 {
    return e.check_id
  }
  let leaf = match e.check_id.split(".").to_array().pop() {
    Some(v) => v.to_owned()
    None => e.check_id
  }
  let path = "specs/\{e.category}/\{leaf}/spec.json"
  let raw = spec_read_file(path)
  if raw.length() == 0 {
    return e.check_id
  }
  let j = @json.parse(raw) catch { _ => Json::null() }
  match j {
    Json::Object(o) =>
      match o.get("title") {
        Some(Json::String(s)) => s
        _ => e.check_id
      }
    _ => e.check_id
  }
}

///| Read the fingerprint field from a per-check spec.json

///|
/// (specs/<category>/<leaf>/spec.json). Returns "" when unavailable.
fn spec_fingerprint_of(e : SpecEntry) -> String {
  if e.fingerprint.length() > 0 {
    return e.fingerprint
  }
  if e.category.length() == 0 {
    return ""
  }
  let leaf = match e.check_id.split(".").to_array().pop() {
    Some(v) => v.to_owned()
    None => e.check_id
  }
  let raw = spec_read_file("specs/\{e.category}/\{leaf}/spec.json")
  if raw.length() == 0 {
    return ""
  }
  let j = @json.parse(raw) catch { _ => Json::null() }
  match j {
    Json::Object(o) =>
      match o.get("fingerprint") {
        Some(Json::String(s)) => s
        _ => ""
      }
    _ => ""
  }
}

///| IRON LAW R2: deterministic joint fingerprint over the spec tree.

///| Walks specs/**/spec.json, collects each fingerprint field, sorts the

///| entries by check_id, joins them as "check_id=fingerprint\n" and hashes

///| the result with SHA-256. Returns "" when the spec tree is unavailable

///|
/// (e.g. running from a release bundle without the repo tree).
pub fn specs_fingerprint() -> String {
  let entries = load_specs()
  if entries.length() == 0 {
    return ""
  }
  sort_spec_entries(entries)
  let buf = StringBuilder()
  let mut found = false
  for e in entries {
    let fp = spec_fingerprint_of(e)
    if fp.length() == 0 {
      continue
    }
    ignore(buf.write_string("\{e.check_id}=\{fp}\n"))
    found = true
  }
  if !found {
    return ""
  }
  let hex = @crypto.bytes_to_hex_string(
    @crypto.sha256(@utf8.encode(buf.to_string())),
  )
  "sha256:\{hex}"
}

///|
/// In-place insertion sort of spec entries by check_id (deterministic order).
fn sort_spec_entries(a : Array[SpecEntry]) -> Unit {
  for i in 1..<a.length() {
    let mut j = i
    while j > 0 && a[j].check_id < a[j - 1].check_id {
      let tmp = a[j]
      a[j] = a[j - 1]
      a[j - 1] = tmp
      j -= 1
    }
  }
}

///| Render the check category list as JSON (name/description pairs),

///|
/// spec-driven when possible. Same single source as list_checks_spec().
pub fn list_checks_meta_json() -> Json {
  let entries = load_specs()
  let items : Array[Json] = []
  if entries.length() == 0 {
    // Fallback: parse the static catalog rendered by list_checks_spec().
    for line in list_checks_spec() {
      let parts = line.split(" — ").to_array()
      let name = parts[0].to_owned()
      let desc = if parts.length() > 1 { parts[1].to_owned() } else { "" }
      items.push(
        Json::object({
          "name": Json::string(name),
          "description": Json::string(desc),
        }),
      )
    }
    return Json::array(items)
  }
  for e in entries {
    let desc = resolve_title(e)
    let fp = if e.fingerprint.length() > 0 { " (\{e.fingerprint})" } else { "" }
    items.push(
      Json::object({
        "name": Json::string(e.check_id),
        "description": Json::string(desc + fp),
      }),
    )
  }
  Json::array(items)
}

///|
/// Render the check category list, spec-driven when possible.
pub fn list_checks_spec() -> Array[String] {
  let entries = load_specs()
  if entries.length() == 0 {
    // Fallback: static catalog matching the v0.8.0 baseline.
    return [
      "initialize — jsonrpc, server_info, protocol_version", "capabilities — response structure",
      "tools/list — tool schema (name, description mandatory)", "tools/call — error path (-32601 for unknown tool)",
      "notifications — session liveness after unknown notifications", "idempotency — repeated identical requests",
      "resources/list, resources/read — resource schema + error path", "prompts/list — prompt schema (name mandatory)",
      "ping, keepalive — spec-mandated ping + session stability", "protocol negotiation — version matrix (4 protocols)",
      "logging/setLevel — logging capability", "completion/complete — prompt completion",
      "resources/subscribe — subscription capability", "sampling/createMessage — sampling capability",
      "batch — JSON-RPC batch request handling", "id_matching — JSON-RPC id matching between request and response",
      "error_schema — Error response schema conformance (code/message)", "resources_read_error — resources/read error path (-32602 / missing resource)",
      "notifications_initialized — initialized notification handling", "stateless/server_discover — server/discover implemented (SEP-2575)",
      "stateless/version_negotiation — inline -32022 negotiation (SEP-2575)", "stateless/self_describing — per-request _meta required (SEP-2575)",
      "stateless/missing_capability — -32021 required capability (SEP-2575)", "stateless/list_cache — ttlMs + cacheScope on list results (SEP-2549)",
      "stateless/schema_2020_12 — full JSON Schema 2020-12 (SEP-2106)", "stateless/resource_error_code — -32602 resource error (SEP-2164)",
      "stateless/mrtr — input_required round-trip (SEP-2322)", "stateless/deprecations — deprecated capability annotation (SEP-2577)",
    ]
  }
  let out : Array[String] = []
  for e in entries {
    let title = resolve_title(e)
    let fp = if e.fingerprint.length() > 0 { " (\{e.fingerprint})" } else { "" }
    out.push("\{e.check_id} — \{title}\{fp}")
  }
  out
}
