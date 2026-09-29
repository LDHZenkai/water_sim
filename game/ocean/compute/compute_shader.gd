extends RefCounted
## SPIR-V for one compute shader in this folder. Uses the imported
## RDShaderFile when the project has been imported (editor, export); otherwise
## compiles the GLSL source directly, so a fresh checkout run straight from the
## command line still gets the GPU ocean.

static func spirv(name: String) -> RDShaderSPIRV:
 var path := "res://ocean/compute/%s.glsl" % name
 var result: RDShaderSPIRV = null
 if FileAccess.file_exists(path + ".import") and ResourceLoader.exists(path):
  var file := ResourceLoader.load(path) as RDShaderFile
  if file != null:
   result = file.get_spirv()
 if result == null or not result.compile_error_compute.is_empty():
  var source := RDShaderSource.new()
  source.language = RenderingDevice.SHADER_LANGUAGE_GLSL
  source.source_compute = FileAccess.get_file_as_string(path).replace("#[compute]", "")
  result = RenderingServer.get_rendering_device().shader_compile_spirv_from_source(source)
 if not result.compile_error_compute.is_empty():
  push_error("Ocean compute shader %s: %s" % [name, result.compile_error_compute])
 return result
