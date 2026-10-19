///| Native-target implementations of the report filesystem primitives

///| (moonbitlang/x/fs). The js counterpart lives in `report_fs_js.mbt`.

///|
/// mkdir -p (native, sync): create every missing path segment.
fn fs_mkdir_p(dir : String) -> Int32 {
  let segments = Array(capacity=8)
  for seg in dir.split("/") {
    for sub in seg.split("\\") {
      segments.push(sub)
    }
  }
  let mut cur = ""
  for seg in segments {
    if seg.length() == 0 {
      continue
    }
    cur = if cur.length() == 0 {
      seg.to_owned()
    } else {
      cur + "/" + seg.to_owned()
    }
    @fs.create_dir(cur) catch {
      _ => ()
    }
  }
  0
}

///|
/// write file (native, sync).
fn fs_write_file(path : String, content : String) -> Int32 {
  @fs.write_string_to_file(path, content) catch {
    _ => ()
  }
  0
}
