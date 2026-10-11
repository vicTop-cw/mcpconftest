///| Native-target implementation of spec manifest reading.
///| Returns file content, or "" when missing/unreadable.
fn spec_read_file(path : String) -> String {
  @fs.read_file_to_string(path) catch { _ => "" }
}
