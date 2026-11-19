-- =============================================================================
-- GeoGhost: the 3-reporter auto-hide puts the post back into review instead of
-- rejecting it (add-reporting-and-blocking, content-safety › 多人举报后暂时隐藏并重新审核).
--
-- No new status. A post under re-review is `pending` with `published_at` set:
-- first-time posts in review have never been published, so `published_at` is
-- null for them. That keeps every existing rule for `pending` (others can't see
-- it, the author sees "in review", it is in the console's pending queue), and
-- its open reports keep it in the reported queue too.
--
--   report_post:    threshold reached on a public post -> pending (was hidden).
--   moderate_post:  approve a re-review -> public again without counting toward
--                   the author's trust a second time; reject -> hidden (unchanged).
--   admin_stats:    a re-review waits since its first open report, not since the
--                   post was created.
--   Existing posts auto-hidden before this migration (hidden, never rejected:
--   they still have open reports) are moved back into review.
--
-- Apply in the Supabase SQL Editor after 20261112020000_hide_reported_from_reporter.sql.
-- create or replace keeps the existing grants.
-- =============================================================================

create or replace function public.report_post(post_id uuid, reason text, note text default null)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  uid     uuid := auth.uid();
  v_post  public.posts;
  v_note  text := nullif(btrim(report_post.note), '');
  used    integer;
begin
  if uid is null then
    raise exception 'not authenticated' using errcode = '42501', hint = 'not_authenticated';
  end if;
  if report_post.reason is null or char_length(report_post.reason) not between 1 and 32 then
    raise exception 'invalid reason' using errcode = '22023', hint = 'invalid_argument';
  end if;
  if v_note is not null and char_length(v_note) > 500 then
    raise exception 'note too long' using errcode = '22023', hint = 'invalid_argument';
  end if;

  select * into v_post from public.posts p
  where p.id = report_post.post_id and p.status in ('public', 'hidden')
  for update;
  if not found then
    raise exception 'post not found' using errcode = 'P0002', hint = 'not_found';
  end if;

  if exists (select 1 from public.reports r
             where r.reporter_id = uid and r.post_id = v_post.id) then
    return jsonb_build_object('ok', true);
  end if;

  perform pg_advisory_xact_lock(hashtextextended('reports:' || uid::text, 0));
  select count(*) into used from public.reports r
  where r.reporter_id = uid and r.created_at >= private.utc_day_start();
  if used >= private.config('reports_per_day') then
    raise exception 'daily report limit reached' using hint = 'reports_day';
  end if;

  insert into public.reports (reporter_id, post_id, reason, note)
  values (uid, v_post.id, report_post.reason, v_note);

  if v_post.status = 'public' then
    select count(*) into used from public.reports r
    where r.post_id = v_post.id and r.resolved_at is null;
    if used >= private.config('report_hide_threshold') then
      -- Temporarily hidden, waiting for the operator: back into review.
      update public.posts p set status = 'pending' where p.id = v_post.id;
    end if;
  end if;

  return jsonb_build_object('ok', true);
end;
$$;

create or replace function public.moderate_post(post_id uuid, decision text)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_post public.posts;
begin
  if moderate_post.decision is null or moderate_post.decision not in ('approve', 'reject') then
    raise exception 'decision must be approve or reject' using errcode = '22023', hint = 'invalid_argument';
  end if;
  select * into v_post from public.posts p where p.id = moderate_post.post_id for update;
  if not found then
    raise exception 'post not found' using errcode = 'P0002', hint = 'not_found';
  end if;

  if moderate_post.decision = 'approve' then
    if v_post.status in ('pending', 'hidden') then
      update public.posts p
         set status = 'public', published_at = coalesce(p.published_at, now())
       where p.id = v_post.id;
      -- Trust counts first approvals only: a re-review (already published once) is not a new one.
      if v_post.published_at is null then
        update private.profiles pr set approved_count = pr.approved_count + 1
         where pr.id = v_post.author_id;
      end if;
      update public.reports r set resolved_at = now(), resolution = 'dismissed'
       where r.post_id = v_post.id and r.resolved_at is null;
      return jsonb_build_object('post_id', v_post.id, 'status', 'public');
    elsif v_post.status = 'public' then
      -- Keep it: close its open reports.
      update public.reports r set resolved_at = now(), resolution = 'dismissed'
       where r.post_id = v_post.id and r.resolved_at is null;
      return jsonb_build_object('post_id', v_post.id, 'status', 'public');
    end if;
  else
    if v_post.status in ('pending', 'public', 'hidden') then
      update public.posts p set status = 'hidden' where p.id = v_post.id;
      update public.reports r set resolved_at = now(), resolution = 'upheld'
       where r.post_id = v_post.id and r.resolved_at is null;
      return jsonb_build_object('post_id', v_post.id, 'status', 'hidden');
    end if;
  end if;

  raise exception 'cannot moderate a post in status %', v_post.status
    using errcode = '55000', hint = 'invalid_status';
end;
$$;

create or replace function public.admin_stats()
returns jsonb
language sql stable security definer set search_path = ''
as $$
  with open_reports as (
    select r.post_id, min(r.created_at) as first_at
      from public.reports r
     where r.resolved_at is null
     group by r.post_id
  )
  select jsonb_build_object(
    'pending_count',     (select count(*) from public.posts where status = 'pending'),
    -- A re-review (published before) waits since its first open report.
    'oldest_pending_at', (select min(case when p.published_at is not null then coalesce(o.first_at, p.created_at)
                                          else p.created_at end)
                            from public.posts p left join open_reports o on o.post_id = p.id
                           where p.status = 'pending'),
    'reported_count',    (select count(*) from open_reports o
                            join public.posts p on p.id = o.post_id
                           where p.status <> 'removed'),
    'oldest_report_at',  (select min(o.first_at) from open_reports o
                            join public.posts p on p.id = o.post_id
                           where p.status <> 'removed'));
$$;

-- Posts auto-hidden before this migration: hidden with open reports (an operator
-- rejection closes them as upheld) and published once -> back into review.
update public.posts p
   set status = 'pending'
 where p.status = 'hidden'
   and p.published_at is not null
   and exists (select 1 from public.reports r where r.post_id = p.id and r.resolved_at is null);
