set pagesize 9999
set linesize 9999
select username,'NEVER_LOGGED_IN' as "STATUS" from dba_users where account_status='OPEN' and username 
not in ( select username from dba_audit_trail where action_name 
in ('LOGOFF','LOGON') and username is not null );

select username,TO_CHAR (TIMESTAMP, 'YYYY-MON-DD HH24:MI:SS') as "LAST_SUCCESSFUL_LOGIN" , returncode from
(
SELECT username, timestamp, returncode, max(TO_DATE (TO_CHAR (TIMESTAMP, 'YYYY-MON-DD HH24:MI:SS'),'YYYY-MON-DD HH24:MI:SS')) over (partition by username) as max_ts
from dba_audit_trail
where action_name = 'LOGON'
and returncode = 0
) a
where timestamp = a.max_ts
order by username asc;
select username,TO_CHAR (TIMESTAMP, 'YYYY-MON-DD HH24:MI:SS') as "LAST_FAILED_LOGIN" , returncode from
(
SELECT username, timestamp, returncode, max(TO_DATE (TO_CHAR (TIMESTAMP, 'YYYY-MON-DD HH24:MI:SS'),'YYYY-MON-DD HH24:MI:SS')) over (partition by username) as "MAX_TS"
from dba_audit_trail
where action_name = 'LOGON'
and returncode > 0
) a
where timestamp = a."MAX_TS"
order by username asc;

