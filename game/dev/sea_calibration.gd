extends SceneTree
## Try a sea state before committing it to default_sea.tres: prints the
## significant height, the long-wave components and the ship's peak pitch and
## roll over 120 s (the waterline tests allow pitch <= 4 and roll <= 3 deg).
##   godot --headless --path game -s res://dev/sea_calibration.gd -- --wind_speed=10 --swell_height=3 --knots=6
## Any exported sea_state.gd property can be overridden; --knots sets the current.

func _initialize() -> void:
 var sea = load("res://ocean/default_sea.tres")
 for arg in OS.get_cmdline_user_args():
  var key := arg.get_slice("=",0).trim_prefix("--")
  var value := arg.get_slice("=",1)
  if key == "knots": sea.current = Vector2(-float(value)*0.514444, 0.0)
  elif key in sea: sea.set(key, float(value))
  else: push_warning("Unknown sea property: " + key)
 print("Hs total=", sea.significant_height(), " m; wind peak period=", TAU/sea.wind_peak(), " s (wavelength ", TAU*9.81/pow(sea.wind_peak(),2), " m); current=", sea.current)
 for count in [24, 32]:
  var table: Dictionary = sea.long_waves(count)
  var variance := 0.0
  var lengths := []
  for i in range(table.count):
   variance += pow(table.amplitude[i],2)/2.0
   lengths.append(snappedf(TAU/Vector2(table.kx[i],table.kz[i]).length(),0.1))
  lengths.sort()
  print(count, " long components: Hs(long band)=", 4.0*sqrt(variance), " m; wavelengths=", lengths)
  var motion = preload("res://ocean/buoyancy.gd").new()
  var pitch := 0.0
  var roll := 0.0
  var start := Time.get_ticks_msec()
  for i in range(7200):
   motion.step(float(i+1)/60.0,1.0/60.0,count)
   pitch = maxf(pitch, absf(rad_to_deg(motion.pitch)))
   roll = maxf(roll, absf(rad_to_deg(motion.roll)))
  print("  peak pitch=", pitch, " deg, roll=", roll, " deg; buoyancy ", float(Time.get_ticks_msec()-start)/7200.0, " ms per tick")
 quit()
