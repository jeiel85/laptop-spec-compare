-- 공개용으로 기준 기기 이름을 익명화해요
update public.scores
   set nickname = '기준 노트북 (1,000점)'
 where device_id = '00000000-0000-4000-8000-000000000001';
