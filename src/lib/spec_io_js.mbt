///| JS-target implementation of spec manifest reading.
extern "js" fn spec_read_file(path : String) -> String =
  #| (path) => {
  #|   try {
  #|     const fs = process.getBuiltinModule('node:fs')
  #|     return fs.readFileSync(path, 'utf8')
  #|   } catch (e) {
  #|     return ''
  #|   }
  #| }
