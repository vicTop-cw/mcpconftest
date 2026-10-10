///| Test suite for mcpconftest (in-package tests).

///| Test: CheckResult constructors work correctly.
test "check_result_pass" {
  let r = @lib.CheckResult::pass("name", "message")
  assert_eq(r.name, "name")
  assert_eq(r.severity, @lib.Pass)
  assert_eq(r.evidence, None)
}

///| Test: CheckResult fail constructor works.
test "check_result_fail" {
  let r = @lib.CheckResult::fail("name", "message", "evidence")
  assert_eq(r.severity, @lib.Fail)
  match r.evidence {
    Some(e) => assert_eq(e, "evidence")
    None => assert_eq("evidence", "should be Some")
  }
}

///| Test: Report summarize works.
test "report_summarize" {
  let results : Array[@lib.CheckResult] = [
    @lib.CheckResult::pass("a", "msg"),
    @lib.CheckResult::pass("b", "msg"),
    @lib.CheckResult::fail("c", "msg", "ev"),
  ]
  let report = @lib.build_report(results, "test", "2026-07-28", "now")
  let summary = report.summarize()
  assert_eq(summary.get("pass"), Some(2))
  assert_eq(summary.get("fail"), Some(1))
}

///| Test: Report has_failures works.
test "report_has_failures" {
  let results : Array[@lib.CheckResult] = [@lib.CheckResult::pass("a", "msg")]
  let report = @lib.build_report(results, "test", "2026-07-28", "now")
  assert_eq(report.has_failures(), false)
}

// ---------------------------------------------------------------------------
// JSON-RPC 2.0 deep check validation tests
// ---------------------------------------------------------------------------

///| Helper: a result-only response with the given id.
fn mk_result_resp(id : Json) -> Json {
  Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": id,
    "result": Json::object({}),
  })
}

///| Helper: an error response with the given id/code/message (optionally with
///| injected coexistence and bad shape).
fn mk_error_resp(
  id : Json,
  code : Double,
  message : String,
  coexist : Bool,
  nonobject_error : Bool,
) -> Json {
  let error_json = if nonobject_error {
    Json::string("not-an-object")
  } else {
    Json::object({
      "code": Json::number(code),
      "message": Json::string(message),
    })
  }
  let obj = if coexist {
    {
      "jsonrpc": Json::string("2.0"),
      "id": id,
      "result": Json::object({}),
      "error": error_json,
    }
  } else {
    {
      "jsonrpc": Json::string("2.0"),
      "id": id,
      "error": error_json,
    }
  }
  Json::object(obj)
}

///| Test: validate_batch_resp accepts a valid batch response.
test "batch_valid_array" {
  let results : Array[@lib.CheckResult] = []
  let resp = Json::array([
    mk_result_resp(Json::number(1.0)),
    mk_result_resp(Json::number(42.0)),
    mk_error_resp(Json::string("req-batch-err"), -32601.0, "Method not found", false, false),
  ])
  let req_ids : Array[Json] = [Json::number(1.0), Json::number(42.0), Json::string("req-batch-err")]
  let err_req_ids : Array[Json] = [Json::string("req-batch-err")]
  @lib.validate_batch_resp(resp, req_ids, err_req_ids, results)
  assert_eq(@lib.count(results, "fail"), 0)
  // array + count + 3 id_match + error_schema = 6
  assert_eq(@lib.count(results, "pass"), 6)
}

///| Test: validate_batch_resp rejects a non-array response.
test "batch_not_array" {
  let results : Array[@lib.CheckResult] = []
  let resp = mk_result_resp(Json::number(1.0))
  let req_ids : Array[Json] = [Json::number(1.0)]
  let err_req_ids : Array[Json] = []
  @lib.validate_batch_resp(resp, req_ids, err_req_ids, results)
  assert_eq(@lib.count(results, "fail"), 1)
}

///| Test: validate_batch_resp rejects count mismatch.
test "batch_count_mismatch" {
  let results : Array[@lib.CheckResult] = []
  let resp = Json::array([mk_result_resp(Json::number(1.0))])
  let req_ids : Array[Json] = [Json::number(1.0), Json::number(42.0)]
  let err_req_ids : Array[Json] = []
  @lib.validate_batch_resp(resp, req_ids, err_req_ids, results)
  // count mismatch (1) + missing id 42 (1)
  assert_eq(@lib.count(results, "fail"), 2)
}

///| Test: validate_batch_resp rejects an unmatched id.
test "batch_id_mismatch" {
  let results : Array[@lib.CheckResult] = []
  let resp = Json::array([mk_result_resp(Json::number(99.0))])
  let req_ids : Array[Json] = [Json::number(1.0)]
  let err_req_ids : Array[Json] = []
  @lib.validate_batch_resp(resp, req_ids, err_req_ids, results)
  // count matches (1==1) but id 1 is missing
  assert_eq(@lib.count(results, "fail"), 1)
}

///| Test: validate_batch_resp rejects an error item without an error object.
test "batch_error_schema_missing" {
  let results : Array[@lib.CheckResult] = []
  let resp = Json::array([mk_result_resp(Json::string("req-batch-err"))])
  let req_ids : Array[Json] = [Json::string("req-batch-err")]
  let err_req_ids : Array[Json] = [Json::string("req-batch-err")]
  @lib.validate_batch_resp(resp, req_ids, err_req_ids, results)
  assert_eq(@lib.count(results, "fail"), 1)
}

///| Test: validate_error_object accepts a schema-valid error response.
test "error_schema_valid" {
  let results : Array[@lib.CheckResult] = []
  let resp = mk_error_resp(Json::number(1.0), -32601.0, "Method not found", false, false)
  let e : Map[String, Json] = match (if resp is Object(obj) { obj.get("error") } else { None }) {
    Some(Json::Object(o)) => o
    _ => Map([])
  }
  @lib.validate_error_object(resp, e, "err", results)
  assert_eq(@lib.count(results, "fail"), 0)
  // jsonrpc + exclusive + code + message + data = 5
  assert_eq(@lib.count(results, "pass"), 5)
}

///| Test: validate_error_object rejects bad code, empty message and
///| result+error coexistence in one shot.
test "error_schema_bad_code_coexist_empty_message" {
  let results : Array[@lib.CheckResult] = []
  let resp = mk_error_resp(Json::number(1.0), 0.5, "", true, false)
  let e : Map[String, Json] = match (if resp is Object(obj) { obj.get("error") } else { None }) {
    Some(Json::Object(o)) => o
    _ => Map([])
  }
  @lib.validate_error_object(resp, e, "err", results)
  // exclusive (1) + code non-integer (1) + empty message (1) = 3
  assert_eq(@lib.count(results, "fail"), 3)
}

///| Test: validate_error_object rejects out-of-range error code.
test "error_schema_code_out_of_range" {
  let results : Array[@lib.CheckResult] = []
  let resp = mk_error_resp(Json::number(1.0), -31999.0, "x", false, false)
  let e : Map[String, Json] = match (if resp is Object(obj) { obj.get("error") } else { None }) {
    Some(Json::Object(o)) => o
    _ => Map([])
  }
  @lib.validate_error_object(resp, e, "err", results)
  assert_eq(@lib.count(results, "fail"), 1)
}

///| Test: validate_id_match accepts exact number-id echo.
test "id_match_number_valid" {
  let results : Array[@lib.CheckResult] = []
  let resp = mk_result_resp(Json::number(42.0))
  @lib.validate_id_match(resp, Json::number(42.0), "id", results)
  assert_eq(@lib.count(results, "fail"), 0)
}

///| Test: validate_id_match rejects type mismatch (string vs number).
test "id_match_type_mismatch" {
  let results : Array[@lib.CheckResult] = []
  let resp = mk_result_resp(Json::string("req-1"))
  @lib.validate_id_match(resp, Json::number(1.0), "id", results)
  assert_eq(@lib.count(results, "fail"), 1)
}

///| Test: validate_id_match accepts exact string-id echo with special chars.
test "id_match_string_special" {
  let results : Array[@lib.CheckResult] = []
  let resp = mk_result_resp(Json::string("req a#b&é"))
  @lib.validate_id_match(resp, Json::string("req a#b&é"), "id", results)
  assert_eq(@lib.count(results, "fail"), 0)
}
