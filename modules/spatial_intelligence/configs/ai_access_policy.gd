class_name AIAccessPolicy
extends RefCounted
## Local session capability policy. A multi-user host must supply authenticated roles.
enum Role { ANALYST, OPERATOR }
var role := Role.ANALYST
var cloud_enabled := false
var actions_enabled := false
var local_enabled := false
var configuration_enabled := true # Standalone OS owner; an authenticated host may deny it.
func allows_connection(profile:Dictionary)->bool:
	return local_enabled if CortexProviders.loopback(str(profile.get("endpoint",""))) else cloud_enabled
func allows_action() -> bool:
	return role == Role.OPERATOR and actions_enabled
