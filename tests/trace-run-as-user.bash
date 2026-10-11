# Sourced by the test drivers right after lib.sh. Records every run_as_user
# call as "run_as_user <cmd...>" in $CALLS and runs it through the sudo stub,
# which only executes commands that are safe inside the sandbox (no real
# kubectl/volta/etc. on the test machine). The real implementation stays
# available as __glimt_real_run_as_user.
eval "__glimt_real_run_as_user() $(declare -f run_as_user | tail -n +2)"
run_as_user() {
  echo "run_as_user $*" >>"$CALLS"
  sudo -u "$REAL_USER" "$@"
}
