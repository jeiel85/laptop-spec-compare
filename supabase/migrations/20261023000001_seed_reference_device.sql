insert into public.scores
  (device_id, nickname, kind, os, cpu, gpu, threads, ram_gb,
   single_pts, multi_pts, gpu_pts, single_raw, multi_raw, bench_version, browser)
values
  ('00000000-0000-4000-8000-000000000001', '기준 노트북 (1,000점)', 'laptop', 'Windows 11',
   'Core 5 210H', 'Intel Graphics (48EU)', 12, 32,
   1000, 1000, 1050, 1.41, 7.95, 1, 'Chromium');
