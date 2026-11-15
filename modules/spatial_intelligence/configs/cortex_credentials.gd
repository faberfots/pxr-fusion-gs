class_name CortexCredentials
extends RefCounted
## Secrets never enter settings documents, scenes, diagnostics or provider catalogs.
static var _sessions:Dictionary={}
static func slot(profile:Dictionary)->String:
	return str(profile.id)+"-"+str(profile.endpoint).sha256_text().substr(0,24)
static func vault_available()->bool:return OS.get_name()=="Windows" and ClassDB.class_exists("CortexCredentialVault")
static func resolve(profile:Dictionary)->String:
	match profile.get("credential_source",""):
		"session":return _sessions.get(slot(profile),"")
		"environment":return OS.get_environment(profile.get("environment","")).strip_edges()
		"vault":
			if vault_available():
				var vault:Object=ClassDB.instantiate("CortexCredentialVault");return str(vault.call("read_secret",slot(profile)))
	return ""
static func store(profile:Dictionary,secret:String)->Error:
	if secret.is_empty() or secret.length()>4096 or "\n" in secret or "\r" in secret or secret.to_utf8_buffer().has(0):return ERR_INVALID_DATA
	match profile.get("credential_source",""):
		"session":_sessions[slot(profile)]=secret;return OK
		"vault":
			if not vault_available():return ERR_UNAVAILABLE
			var vault:Object=ClassDB.instantiate("CortexCredentialVault")
			return OK if vault.call("write_secret",slot(profile),secret) else ERR_CANT_CREATE
	return ERR_INVALID_PARAMETER
static func forget(profile:Dictionary)->void:
	_sessions.erase(slot(profile))
	if profile.get("credential_source")=="vault" and vault_available():
		var vault:Object=ClassDB.instantiate("CortexCredentialVault");vault.call("delete_secret",slot(profile))
static func clear_sessions()->void:_sessions.clear()
static func present(profile:Dictionary)->bool:return not resolve(profile).is_empty()
