///| JS-target implementations of the report filesystem primitives.

///|
/// Native counterpart lives in `report_fs_native.mbt`.
extern "js" fn fs_mkdir_p(dir : String) -> Int32 =
  #| (dir) => {
  #|   try {
  #|     const fs = process.getBuiltinModule('node:fs')
  #|     fs.mkdirSync(dir, { recursive: true })
  #|     return 0
  #|   } catch (e) {
  #|     return -1
  #|   }
  #| }

///|
extern "js" fn fs_write_file(path : String, content : String) -> Int32 =
  #| (path, content) => {
  #|   try {
  #|     const fs = process.getBuiltinModule('node:fs')
  #|     fs.writeFileSync(path, content, 'utf8')
  #|     return 0
  #|   } catch (e) {
  #|     return -1
  #|   }
  #| }
