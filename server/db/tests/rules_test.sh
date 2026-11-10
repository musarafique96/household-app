#!/usr/bin/env bash
# Checks the Phase 1 database rules. Usage: PGHOST=... PGPORT=... PGUSER=... DB=gharbaar_test ./rules_test.sh
# The database must be empty of the test ids; the script truncates users first.
set -u
DB=${DB:?set DB to a disposable test database}
P="psql -d $DB -q -v ON_ERROR_STOP=1"
ERR=$(mktemp)
fails=0
expect_ok()   { if $P -c "$1" >/dev/null 2>"$ERR"; then echo "PASS allowed: $2"; else echo "FAIL should be allowed: $2 -- $(cat "$ERR")"; fails=$((fails+1)); fi; }
expect_fail() { if $P -c "$1" >/dev/null 2>"$ERR"; then echo "FAIL should be blocked: $2"; fails=$((fails+1)); else echo "PASS blocked: $2"; fi; }

$P -c "truncate users cascade;" >/dev/null 2>&1
expect_ok   "insert into users(id,username,email) values ('00000000-0000-0000-0000-000000000001','musa','rafique.musa96@gmail.com');" "create user with username and Gmail"
expect_ok   "insert into users(id,username,phone) values ('00000000-0000-0000-0000-000000000002','ali','+966554807219');" "create user with username and phone"
expect_fail "insert into users(id,username) values ('00000000-0000-0000-0000-000000000009','musa');" "duplicate username"
expect_fail "insert into users(username) values ('MUSA');" "uppercase username"
expect_fail "update users set username='musa2' where id='00000000-0000-0000-0000-000000000001';" "change username after creation"
expect_fail "update users set email='other@gmail.com' where id='00000000-0000-0000-0000-000000000001';" "change linked Gmail"
expect_ok   "update users set phone='+966500000001' where id='00000000-0000-0000-0000-000000000002';" "change phone number"
expect_fail "insert into users(id) values ('00000000-0000-0000-0000-000000000010');" "user with no sign-in identifier"
expect_ok   "insert into households(id,name,created_by) values ('10000000-0000-0000-0000-000000000001','Musa house','00000000-0000-0000-0000-000000000001');" "create household"
expect_ok   "insert into household_members(household_id,user_id,role) values ('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000001','head');" "add head"
expect_ok   "insert into household_members(household_id,user_id,role) values ('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002','member');" "add member"
expect_fail "begin; delete from household_members where household_id='10000000-0000-0000-0000-000000000001' and role='head'; commit;" "remove the only head while a member remains"
expect_ok   "begin; update household_members set role='head' where household_id='10000000-0000-0000-0000-000000000001' and user_id='00000000-0000-0000-0000-000000000002'; update household_members set left_at=now() where household_id='10000000-0000-0000-0000-000000000001' and user_id='00000000-0000-0000-0000-000000000001'; commit;" "hand over head, then old head leaves"

rm -f "$ERR"
echo "failures: $fails"
exit $fails
