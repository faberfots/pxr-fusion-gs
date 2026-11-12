class_name AIAccessPolicy
extends RefCounted
## Local session capability policy. A multi-user host must supply authenticated roles.
enum Role { ANALYST, OPERATOR }
var role := Role.ANALYST
var cloud_enabled := false
var actions_enabled := false
func allows_action() -> bool:
	return role == Role.OPERATOR and actions_enabled
