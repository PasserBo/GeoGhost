-- =============================================================================
-- GeoGhost: a post the caller reported is hidden from the caller at once
-- (add-reporting-and-blocking, content-safety › 举报后自己不再看到; App Review 1.2).
--
-- The public-posts read policy gains "not reported by me". `explore` is security
-- invoker, so it follows the policy without changes; likes / saves inserts check
-- visibility through the same policy. Other users are unaffected until the
-- 3-reporter auto-hide or the operator acts. The reporter keeps not seeing it
-- even after the report is resolved (the report row stays).
--
-- Apply in the Supabase SQL Editor after 20261112010000_moderation_console.sql.
-- =============================================================================

-- reports is unreadable for clients, so the check runs with the owner's rights.
-- Uses the unique (reporter_id, post_id) index.
create function private.reported_by_me(post uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.reports r
    where r.reporter_id = (select auth.uid()) and r.post_id = post);
$$;

revoke all on function private.reported_by_me(uuid) from public, anon, authenticated;
grant execute on function private.reported_by_me(uuid) to anon, authenticated;

drop policy posts_select_public on public.posts;
create policy posts_select_public on public.posts
  for select to anon, authenticated
  using (status = 'public' and private.author_visible(author_id) and not private.reported_by_me(id));
