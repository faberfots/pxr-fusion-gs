extends SceneTree
func _initialize()->void:run.call_deferred()
func run()->void:
	var args:=OS.get_cmdline_user_args()
	if args.size()!=2:quit(2);return
	var profile:=CortexProviders.profile("compatible");profile.id="restart-check-"+args[1];profile.credential_source="vault"
	var expected:="synthetic-credential-for-restart"
	var passed:=false
	if args[0]=="write":passed=CortexCredentials.store(profile,expected)==OK
	elif args[0]=="read":
		passed=CortexCredentials.resolve(profile)==expected
		CortexCredentials.forget(profile)
		passed=passed and CortexCredentials.resolve(profile).is_empty()
	print("VAULT RESTART ",args[0],": ","PASS" if passed else "FAIL")
	quit(0 if passed else 1)
