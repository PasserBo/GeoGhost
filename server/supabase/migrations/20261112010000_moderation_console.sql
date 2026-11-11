-- =============================================================================
-- GeoGhost moderation console (docs/spec/changes/add-moderation-console/design.md)
-- Everything here is for the service role only: the admin Worker calls it after
-- Cloudflare Access has identified the operator, and passes their email as `actor`.
-- =============================================================================

create table private.moderation_log (
  id      bigint generated always as identity primary key,
  at      timestamptz not null default now(),
  actor   text not null check (char_length(actor) between 1 and 320),
  action  text not null check (action in ('approve', 'reject', 'remove', 'ban', 'unban')),
  -- No foreign keys: the log outlives deleted posts and accounts.
  post_id uuid,
  user_id uuid,
  note    text check (char_length(note) <= 500)
);
alter table private.moderation_log enable row level security;  -- no policies: definer functions only
create index moderation_log_at_idx on private.moderation_log (at desc);

-- -----------------------------------------------------------------------------
-- Overview: what is waiting and for how long.
-- -----------------------------------------------------------------------------
create function public.admin_stats()
returns jsonb
language sql stable security definer set search_path = ''
as $$
  select jsonb_build_object(
    'pending_count',     (select count(*) from public.posts where status = 'pending'),
    'oldest_pending_at', (select min(created_at) from public.posts where status = 'pending'),
    'reported_count',    (select count(distinct r.post_id) from public.reports r
                            join public.posts p on p.id = r.post_id
                           where r.resolved_at is null and p.status <> 'removed'),
    'oldest_report_at',  (select min(r.created_at) from public.reports r
                            join public.posts p on p.id = r.post_id
                           where r.resolved_at is null and p.status <> 'removed'));
$$;

-- -----------------------------------------------------------------------------
-- Queues. kind = 'pending' (oldest first) or 'reported' (oldest open report first).
-- -----------------------------------------------------------------------------
create function public.admin_queue(kind text, max_rows integer default 50)
returns table (
  id              uuid,
  author_id       uuid,
  status          text,
  post_kind       text,
  locality        text,
  country_code    text,
  captured_on     date,
  width           integer,
  height          integer,
  image_key       text,
  thumb_key       text,
  created_at      timestamptz,
  published_at    timestamptz,
  author_nickname text,
  author_approved integer,
  author_hidden   integer,
  author_banned   boolean,
  open_reports    integer,
  report_reasons  text[],
  first_report_at timestamptz
)
language plpgsql stable security definer set search_path = ''
as $$
begin
  if admin_queue.kind is null or admin_queue.kind not in ('pending', 'reported') then
    raise exception 'kind must be pending or reported' using errcode = '22023', hint = 'invalid_argument';
  end if;
  return query
  with open_reports as (
    select r.post_id, count(*)::integer as n,
           array_agg(distinct r.reason order by r.reason) as reasons,
           min(r.created_at) as first_at
      from public.reports r
     where r.resolved_at is null
     group by r.post_id
  )
  select p.id, p.author_id, p.status, p.kind, p.locality, p.country_code, p.captured_on,
         p.width, p.height, p.image_key, p.thumb_key, p.created_at, p.published_at,
         pr.nickname, coalesce(pr.approved_count, 0),
         (select count(*)::integer from public.posts h where h.author_id = p.author_id and h.status = 'hidden'),
         pr.banned_at is not null,
         coalesce(o.n, 0), coalesce(o.reasons, '{}'::text[]), o.first_at
    from public.posts p
    left join private.profiles pr on pr.id = p.author_id
    left join open_reports o on o.post_id = p.id
   where (admin_queue.kind = 'pending' and p.status = 'pending')
      or (admin_queue.kind = 'reported' and o.n > 0 and p.status <> 'removed')
   order by case when admin_queue.kind = 'pending' then p.created_at else o.first_at end asc
   limit greatest(1, least(coalesce(admin_queue.max_rows, 50), 200));
end;
$$;

create function public.admin_post_reports(post_id uuid)
returns table (reason text, note text, created_at timestamptz, resolved_at timestamptz, resolution text)
language sql stable security definer set search_path = ''
as $$
  select r.reason, r.note, r.created_at, r.resolved_at, r.resolution
    from public.reports r
   where r.post_id = admin_post_reports.post_id
   order by r.created_at;
$$;

-- -----------------------------------------------------------------------------
-- Actions. Each one is logged with the operator's email.
-- -----------------------------------------------------------------------------
create function public.admin_moderate(post_id uuid, decision text, actor text)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  result jsonb;
begin
  result := public.moderate_post(admin_moderate.post_id, admin_moderate.decision);
  insert into private.moderation_log (actor, action, post_id, user_id)
  select admin_moderate.actor, admin_moderate.decision, p.id, p.author_id
    from public.posts p where p.id = admin_moderate.post_id;
  return result;
end;
$$;

-- Marks the post removed (the Worker deletes its images first) and closes its reports.
create function public.admin_remove_post(post_id uuid, actor text)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_post public.posts;
begin
  select * into v_post from public.posts p where p.id = admin_remove_post.post_id for update;
  if not found then
    raise exception 'post not found' using errcode = 'P0002', hint = 'not_found';
  end if;
  if v_post.status <> 'removed' then
    update public.posts p set status = 'removed' where p.id = v_post.id;
  end if;
  update public.reports r set resolved_at = now(), resolution = 'removed'
   where r.post_id = v_post.id and r.resolved_at is null;
  insert into private.moderation_log (actor, action, post_id, user_id)
  values (admin_remove_post.actor, 'remove', v_post.id, v_post.author_id);
  return jsonb_build_object('post_id', v_post.id, 'status', 'removed',
                            'image_key', v_post.image_key, 'thumb_key', v_post.thumb_key);
end;
$$;

-- A banned author can't publish (create_post, complete_post_upload) and none of their posts
-- are visible to others (private.author_visible in the posts policy).
create function public.admin_set_ban(user_id uuid, banned boolean, actor text, note text default null)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
begin
  update private.profiles pr
     set banned_at = case when admin_set_ban.banned then coalesce(pr.banned_at, now()) end
   where pr.id = admin_set_ban.user_id;
  if not found then
    raise exception 'profile not found' using errcode = 'P0002', hint = 'not_found';
  end if;
  insert into private.moderation_log (actor, action, user_id, note)
  values (admin_set_ban.actor, case when admin_set_ban.banned then 'ban' else 'unban' end,
          admin_set_ban.user_id, admin_set_ban.note);
  return jsonb_build_object('user_id', admin_set_ban.user_id, 'banned', admin_set_ban.banned);
end;
$$;

create function public.admin_log(max_rows integer default 50)
returns table (at timestamptz, actor text, action text, post_id uuid, user_id uuid, note text)
language sql stable security definer set search_path = ''
as $$
  select l.at, l.actor, l.action, l.post_id, l.user_id, l.note
    from private.moderation_log l
   order by l.at desc, l.id desc
   limit greatest(1, least(coalesce(admin_log.max_rows, 50), 200));
$$;

-- -----------------------------------------------------------------------------
-- Grants: service role only.
-- -----------------------------------------------------------------------------
revoke all on table private.moderation_log from public, anon, authenticated;
revoke all on function public.admin_stats()                                   from public, anon, authenticated;
revoke all on function public.admin_queue(text, integer)                      from public, anon, authenticated;
revoke all on function public.admin_post_reports(uuid)                        from public, anon, authenticated;
revoke all on function public.admin_moderate(uuid, text, text)                from public, anon, authenticated;
revoke all on function public.admin_remove_post(uuid, text)                   from public, anon, authenticated;
revoke all on function public.admin_set_ban(uuid, boolean, text, text)        from public, anon, authenticated;
revoke all on function public.admin_log(integer)                              from public, anon, authenticated;
grant execute on function public.admin_stats()                                to service_role;
grant execute on function public.admin_queue(text, integer)                   to service_role;
grant execute on function public.admin_post_reports(uuid)                     to service_role;
grant execute on function public.admin_moderate(uuid, text, text)             to service_role;
grant execute on function public.admin_remove_post(uuid, text)                to service_role;
grant execute on function public.admin_set_ban(uuid, boolean, text, text)     to service_role;
grant execute on function public.admin_log(integer)                           to service_role;
