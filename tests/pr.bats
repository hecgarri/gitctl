#!/usr/bin/env bats
load test_helper

setup() {
	setup_repo
	add_check ok 'true'
	git init -q --bare "$TEST_TMP/remote.git"
	git remote add origin "$TEST_TMP/remote.git"
	git push -q origin main
	# gh simulado: registra sus argumentos y responde según el subcomando.
	mkdir -p "$TEST_TMP/bin"
	cat >"$TEST_TMP/bin/gh" <<'G'
#!/usr/bin/env bash
echo "$*" >>"$GH_LOG"
case "$1 $2" in
"pr create") echo "https://github.com/x/y/pull/1" ;;
"pr view") cat "$GH_VIEW" ;;
"pr merge") exit 0 ;;
esac
G
	chmod +x "$TEST_TMP/bin/gh"
	export PATH="$TEST_TMP/bin:$PATH" GH_LOG="$TEST_TMP/gh.log" GH_VIEW="$TEST_TMP/view.json"
}

pr_view() { # sha estado_ci draft
	jq -n --arg sha "$1" --arg ci "$2" --argjson d "${3:-false}" \
		'{url:"https://github.com/x/y/pull/1", state:"OPEN", isDraft:$d, headRefOid:$sha,
		  reviewDecision:"APPROVED", mergeable:"MERGEABLE",
		  statusCheckRollup:[{status:"COMPLETED", conclusion:$ci}]}' >"$GH_VIEW"
}

@test "pr open se niega si la puerta no pasa" {
	task_with_runs fake-a fake-b
	run gitctl pr open t1 fake-a
	assert_failure
	assert_output_contains "la puerta no pasa"
	[[ ! -f "$GH_LOG" ]]
}

@test "pr open --draft hace push y crea el PR con el informe de evidencia" {
	task_with_runs fake-a fake-b
	run gitctl pr open t1 fake-a --draft
	assert_success
	git --git-dir="$TEST_TMP/remote.git" rev-parse --verify -q refs/heads/gitctl/t1/fake-a
	grep -q -- "--draft" "$GH_LOG"
	grep -q -- "--base main --head gitctl/t1/fake-a" "$GH_LOG"
	jq -e '.assignments[0].pr == "https://github.com/x/y/pull/1"' "$(state)/tasks/t1/task.json"
}

@test "pr open con la puerta en verde crea un PR normal" {
	task_with_runs fake-a fake-b
	gitctl verify t1 fake-a
	gitctl review t1 fake-a --by fake-b
	gitctl approve t1 fake-a --yes
	run gitctl pr open t1 fake-a
	assert_success
	run grep -q -- "--draft" "$GH_LOG"
	assert_failure
}

@test "pr merge exige que el HEAD del PR sea el commit evaluado" {
	task_with_runs fake-a fake-b
	gitctl verify t1 fake-a
	gitctl review t1 fake-a --by fake-b
	gitctl approve t1 fake-a --yes
	pr_view "0000000000000000000000000000000000000000" SUCCESS
	run gitctl --yes pr merge t1 fake-a
	assert_failure
	assert_output_contains "no es el commit evaluado"
	run grep -q "pr merge" "$GH_LOG"
	assert_failure
}

@test "pr merge rechaza CI en rojo" {
	task_with_runs fake-a fake-b
	gitctl verify t1 fake-a
	gitctl review t1 fake-a --by fake-b
	gitctl approve t1 fake-a --yes
	pr_view "$(git rev-parse gitctl/t1/fake-a)" FAILURE
	run gitctl --yes pr merge t1 fake-a
	assert_failure
	assert_output_contains "CI de GitHub: fail"
}

@test "pr merge fusiona con --match-head-commit cuando todo está en verde" {
	task_with_runs fake-a fake-b
	gitctl verify t1 fake-a
	gitctl review t1 fake-a --by fake-b
	gitctl approve t1 fake-a --yes
	local sha
	sha="$(git rev-parse gitctl/t1/fake-a)"
	pr_view "$sha" SUCCESS
	run gitctl --yes pr merge t1 fake-a
	assert_success
	grep -q -- "--match-head-commit $sha" "$GH_LOG"
}
