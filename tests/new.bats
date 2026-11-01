#!/usr/bin/env bats
load test_helper

setup() { setup_repo; }

@test "new crea rama y worktree desde main y guarda la base" {
	run env GITCTL_CD_FILE="$CD_FILE" gitctl new feat/login
	assert_success
	[[ -d "$(wt_path feat-login)" ]]
	[[ "$(git -C "$(wt_path feat-login)" branch --show-current)" == "feat/login" ]]
	[[ "$(git config branch.feat/login.gitctl-base)" == "main" ]]
	[[ "$(cat "$CD_FILE")" == "$(wt_path feat-login)" ]]
}

@test "new reutiliza una rama existente sin moverla" {
	git branch vieja
	commit_in . a.txt a
	run gitctl new vieja
	assert_success
	assert_output_contains "reutilizando"
	[[ "$(git rev-parse vieja)" == "$(git rev-parse main~1)" ]]
	[[ "$(git config branch.vieja.gitctl-base)" == "main" ]]
}

@test "new --base usa otra rama local" {
	git branch dev
	run gitctl new x --base dev
	assert_success
	[[ "$(git config branch.x.gitctl-base)" == "dev" ]]
}

@test "new --base rechaza lo que no es una rama local" {
	git tag v1
	run gitctl new x --base v1
	assert_failure
	assert_output_contains "rama local"
	run gitctl new x --base "$(git rev-parse HEAD)"
	assert_failure
	[[ ! -d "$(wt_path x)" ]]
}

@test "new rechaza nombres de rama no válidos" {
	run gitctl new "mal nombre"
	assert_failure
	assert_output_contains "no válido"
}

@test "new no pisa una carpeta existente" {
	mkdir -p "$(wt_path ocupado)"
	run gitctl new ocupado
	assert_failure
	assert_output_contains "ya existe"
	refute git show-ref -q refs/heads/ocupado
}

@test "new falla si la rama ya tiene worktree y sugiere cd" {
	gitctl new x >/dev/null 2>&1
	run gitctl new x
	assert_failure
	assert_output_contains "gitctl cd x"
}

@test "new copia los archivos de copy y avisa de los que faltan" {
	echo "A=1" >.env
	mkdir -p config && echo "k: v" >config/local.yml
	set_cfg copy ".env config/local.yml falta.txt ../fuera"
	run gitctl new x
	assert_success
	assert_output_contains "falta.txt"
	assert_output_contains "../fuera"
	[[ "$(cat "$(wt_path x)/.env")" == "A=1" ]]
	[[ -f "$(wt_path x)/config/local.yml" ]]
}

@test "new ejecuta setup dentro del worktree" {
	set_cfg setup "touch LISTO"
	run gitctl new x
	assert_success
	assert_output_contains "setup: touch LISTO"
	[[ -f "$(wt_path x)/LISTO" ]]
	[[ ! -f "$REPO/LISTO" ]]
}

@test "si setup falla, avisa y el worktree se conserva" {
	set_cfg setup "false"
	run gitctl new x
	assert_failure
	assert_output_contains "setup ha fallado"
	[[ -d "$(wt_path x)" ]]
}

@test "new funciona desde dentro de otro worktree" {
	gitctl new a >/dev/null 2>&1
	cd "$(wt_path a)"
	run gitctl new b
	assert_success
	[[ -d "$(wt_path b)" ]]
	[[ "$(git config branch.b.gitctl-base)" == "main" ]]
}
