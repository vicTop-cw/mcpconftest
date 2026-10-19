///|
/// JS-target implementation of the timestamp helper used by probes.
extern "js" fn js_now_iso() -> String =
  #| () => new Date().toISOString()

///|
/// Current UTC time as an ISO-8601 string (js target).
pub fn now_iso() -> String {
  js_now_iso()
}

///|
/// Current time in milliseconds (js target, epoch ms).
pub fn now_ms() -> Int32 {
  js_now_ms()
}
