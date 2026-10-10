///| Native-target implementation of the timestamp helpers used by probes.
///
/// Self-implemented UTC conversion (epoch ms -> ISO-8601) so the native
/// backend does not depend on any JS runtime. Handles leap years via the
/// Howard Hinnant `civil_from_days` algorithm (valid for the full proleptic
/// Gregorian calendar).

///| Current time in milliseconds (native target, epoch ms).
pub fn now_ms() -> Int {
  @env.now().to_int()
}

///| Current UTC time as an ISO-8601 string with millisecond precision
///| (native target), e.g. `2026-10-09T12:34:56.789Z`.
pub fn now_iso() -> String {
  let ms : Int64 = @env.now().to_int64()
  let ms_per_day : Int64 = 86400000L
  let days = ms / ms_per_day
  let day_ms = ms % ms_per_day
  let hh = day_ms / 3600000L
  let mm = (day_ms % 3600000L) / 60000L
  let ss = (day_ms % 60000L) / 1000L
  let millis = day_ms % 1000L
  let (y, mo, d) = civil_from_days(days)
  "\{pad4(y)}-\{pad2(mo)}-\{pad2(d)}T\{pad2(hh)}:\{pad2(mm)}:\{pad2(ss)}.\{pad3(millis)}Z"
}

///| Convert days since 1970-01-01 to a (year, month, day) tuple in the
///| proleptic Gregorian calendar (Howard Hinnant's algorithm).
fn civil_from_days(z : Int64) -> (Int64, Int64, Int64) {
  let z = z + 719468L
  let era = (if z >= 0L { z } else { z - 146096L }) / 146097L
  let doe = z - era * 146097L
  let yoe = (doe - doe / 1460L + doe / 36524L - doe / 146096L) / 365L
  let y = yoe + era * 400L
  let doy = doe - (365L * yoe + yoe / 4L - yoe / 100L)
  let mp = (5L * doy + 2L) / 153L
  let d = doy - (153L * mp + 2L) / 5L + 1L
  let m = if mp < 10L { mp + 3L } else { mp - 9L }
  let y = if m <= 2L { y + 1L } else { y }
  (y, m, d)
}

fn pad2(v : Int64) -> String {
  if v < 10L { "0" + v.to_string() } else { v.to_string() }
}

fn pad3(v : Int64) -> String {
  if v < 10L {
    "00" + v.to_string()
  } else if v < 100L {
    "0" + v.to_string()
  } else {
    v.to_string()
  }
}

fn pad4(v : Int64) -> String {
  if v < 10L {
    "000" + v.to_string()
  } else if v < 100L {
    "00" + v.to_string()
  } else if v < 1000L {
    "0" + v.to_string()
  } else {
    v.to_string()
  }
}
