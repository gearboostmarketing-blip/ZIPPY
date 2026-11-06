-- =====================================================================
-- Zip Receipt v2 – cloud database (Supabase)
-- Paste this whole file into Supabase → SQL Editor → New query → Run.
-- Safe to run again after updates: it only adds what's missing.
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------- tables ----------
create table if not exists public.orgs (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  settings jsonb not null default '{}'::jsonb,        -- receipt template, wording, signatures (shared by every location)
  created_at timestamptz not null default now()
);

create table if not exists public.locations (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.orgs(id) on delete cascade,
  name text not null,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.members (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.orgs(id) on delete cascade,
  user_id uuid unique references auth.users(id) on delete set null,   -- the login; empty until the invite is accepted
  name text not null,
  email text,
  role text not null check (role in ('admin','bookkeeper','staff','viewer')),
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.member_locations (
  member_id uuid not null references public.members(id) on delete cascade,
  location_id uuid not null references public.locations(id) on delete cascade,
  primary key (member_id, location_id)
);

create table if not exists public.invites (
  token text primary key default encode(gen_random_bytes(18), 'hex'),
  org_id uuid not null references public.orgs(id) on delete cascade,
  member_id uuid not null references public.members(id) on delete cascade,
  created_by uuid,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '30 days',
  used_at timestamptz
);

-- Every log line, safe count and month setting is one record. "data" holds the details the app works with.
create table if not exists public.records (
  id text primary key,
  org_id uuid not null references public.orgs(id) on delete cascade,
  location_id uuid not null references public.locations(id) on delete cascade,
  kind text not null check (kind in ('entry','count','meta')),
  person_id uuid references public.members(id) on delete set null,     -- whose advance / expense this is
  data jsonb not null,
  deleted boolean not null default false,
  updated_at timestamptz not null default now(),
  updated_by uuid
);
create index if not exists records_org_updated on public.records (org_id, updated_at);
create index if not exists records_person on public.records (person_id);

-- ---------- who am I? (used by the security rules) ----------
create or replace function public.my_member_id() returns uuid
  language sql stable security definer set search_path = public as
$$ select id from members where user_id = auth.uid() and active $$;

create or replace function public.my_org() returns uuid
  language sql stable security definer set search_path = public as
$$ select org_id from members where user_id = auth.uid() and active $$;

create or replace function public.my_role() returns text
  language sql stable security definer set search_path = public as
$$ select role from members where user_id = auth.uid() and active $$;

create or replace function public.has_location(loc uuid) returns boolean
  language sql stable security definer set search_path = public as
$$ select exists (select 1 from member_locations ml join members m on m.id = ml.member_id
                  where m.user_id = auth.uid() and m.active and ml.location_id = loc) $$;

create or replace function public.can_book(loc uuid) returns boolean
  language sql stable security definer set search_path = public as
$$ select coalesce(
     (my_role() = 'admin' and exists (select 1 from locations where id = loc and org_id = my_org()))
     or (my_role() = 'bookkeeper' and has_location(loc)), false) $$;

create or replace function public.can_view(loc uuid) returns boolean
  language sql stable security definer set search_path = public as
$$ select coalesce(can_book(loc) or (my_role() = 'viewer' and has_location(loc)), false) $$;

-- helpers about another person (run with full rights so the rules below never loop back on themselves)
create or replace function public.member_org(mid uuid) returns uuid
  language sql stable security definer set search_path = public as $$ select org_id from members where id = mid $$;
create or replace function public.member_role(mid uuid) returns text
  language sql stable security definer set search_path = public as $$ select role from members where id = mid $$;
create or replace function public.member_in_my_locations(mid uuid) returns boolean
  language sql stable security definer set search_path = public as
$$ select exists (select 1 from member_locations ml where ml.member_id = mid and has_location(ml.location_id)) $$;

-- ---------- row level security ----------
alter table public.orgs enable row level security;
alter table public.locations enable row level security;
alter table public.members enable row level security;
alter table public.member_locations enable row level security;
alter table public.invites enable row level security;     -- no policies: only the functions below touch invites
alter table public.records enable row level security;

drop policy if exists orgs_read on public.orgs;
create policy orgs_read on public.orgs for select using (id = my_org());
drop policy if exists orgs_admin on public.orgs;
create policy orgs_admin on public.orgs for update using (id = my_org() and my_role() = 'admin') with check (id = my_org());

drop policy if exists loc_read on public.locations;
create policy loc_read on public.locations for select using (org_id = my_org() and (my_role() = 'admin' or has_location(id)));
drop policy if exists loc_insert on public.locations;
create policy loc_insert on public.locations for insert with check (org_id = my_org() and my_role() = 'admin');
drop policy if exists loc_update on public.locations;
create policy loc_update on public.locations for update using (org_id = my_org() and my_role() = 'admin') with check (org_id = my_org());

drop policy if exists mem_read on public.members;
create policy mem_read on public.members for select using (
  org_id = my_org() and (
    my_role() = 'admin' or user_id = auth.uid()
    or (my_role() in ('bookkeeper','viewer') and member_in_my_locations(id))));
drop policy if exists mem_insert on public.members;
create policy mem_insert on public.members for insert with check (
  org_id = my_org() and user_id is null and (my_role() = 'admin' or (my_role() = 'bookkeeper' and role = 'staff')));
drop policy if exists mem_update on public.members;
create policy mem_update on public.members for update using (
  org_id = my_org() and (my_role() = 'admin' or (my_role() = 'bookkeeper' and role = 'staff')))
  with check (org_id = my_org() and (my_role() = 'admin' or role = 'staff'));

drop policy if exists ml_read on public.member_locations;
create policy ml_read on public.member_locations for select using (
  member_org(member_id) = my_org()
  and (my_role() = 'admin' or has_location(location_id) or member_id = my_member_id()));
drop policy if exists ml_insert on public.member_locations;
create policy ml_insert on public.member_locations for insert with check (
  member_org(member_id) = my_org()
  and (my_role() = 'admin' or (my_role() = 'bookkeeper' and member_role(member_id) = 'staff' and has_location(location_id))));
drop policy if exists ml_delete on public.member_locations;
create policy ml_delete on public.member_locations for delete using (
  member_org(member_id) = my_org()
  and (my_role() = 'admin' or (my_role() = 'bookkeeper' and member_role(member_id) = 'staff' and has_location(location_id))));

drop policy if exists rec_read on public.records;
create policy rec_read on public.records for select using (
  org_id = my_org() and (
    can_view(location_id)
    or person_id = my_member_id()                                   -- staff see their own advances and expenses
    or (kind = 'meta' and has_location(location_id))));             -- and the month's exchange rate
drop policy if exists rec_insert on public.records;
create policy rec_insert on public.records for insert with check (
  org_id = my_org() and (
    can_book(location_id)
    or (my_role() = 'staff' and kind = 'entry' and person_id = my_member_id()
        and has_location(location_id) and data->>'type' = 'expense')));
drop policy if exists rec_update on public.records;
create policy rec_update on public.records for update using (
  org_id = my_org() and (
    can_book(location_id)
    or (my_role() = 'staff' and kind = 'entry' and person_id = my_member_id() and coalesce(data->>'locked','') <> 'true')))
  with check (
  org_id = my_org() and (
    can_book(location_id)
    or (my_role() = 'staff' and kind = 'entry' and person_id = my_member_id()
        and has_location(location_id) and data->>'type' = 'expense')));

-- ---------- housekeeping triggers ----------
create or replace function public.records_stamp() returns trigger
  language plpgsql security definer set search_path = public as
$$ begin
  if (select org_id from locations where id = new.location_id) is distinct from new.org_id then
    raise exception 'Location does not belong to this organisation';
  end if;
  new.updated_at := clock_timestamp();
  new.updated_by := auth.uid();
  return new;
end $$;
drop trigger if exists records_stamp on public.records;
create trigger records_stamp before insert or update on public.records for each row execute function public.records_stamp();

-- Never leave an organisation without an active admin.
create or replace function public.keep_an_admin() returns trigger
  language plpgsql security definer set search_path = public as
$$ begin
  if old.role = 'admin' and old.active and (new.role <> 'admin' or not new.active)
     and not exists (select 1 from members where org_id = old.org_id and role = 'admin' and active and id <> old.id) then
    raise exception 'This is the last admin. Make someone else an admin first.';
  end if;
  return new;
end $$;
drop trigger if exists keep_an_admin on public.members;
create trigger keep_an_admin before update on public.members for each row execute function public.keep_an_admin();

-- ---------- actions the apps call ----------
-- First-time setup: the signed-in user creates the organisation and becomes its first admin.
create or replace function public.create_org(org_name text, my_name text, location_name text)
  returns json language plpgsql security definer set search_path = public as
$$ declare o uuid; l uuid; m uuid; begin
  if auth.uid() is null then raise exception 'Sign in first.'; end if;
  if exists (select 1 from members where user_id = auth.uid()) then raise exception 'You already belong to an organisation.'; end if;
  insert into orgs (name) values (org_name) returning id into o;
  insert into locations (org_id, name) values (o, location_name) returning id into l;
  insert into members (org_id, user_id, name, email, role)
    values (o, auth.uid(), my_name, (select email from auth.users where id = auth.uid()), 'admin') returning id into m;
  insert into member_locations values (m, l);
  return json_build_object('org_id', o, 'location_id', l, 'member_id', m);
end $$;

-- Make an invite link for a person (admins: anyone; bookkeepers: their staff).
create or replace function public.create_invite(member uuid)
  returns text language plpgsql security definer set search_path = public as
$$ declare t members%rowtype; tok text; begin
  select * into t from members where id = member and org_id = my_org();
  if not found then raise exception 'Person not found.'; end if;
  if not (my_role() = 'admin' or (my_role() = 'bookkeeper' and t.role = 'staff' and exists (
           select 1 from member_locations ml where ml.member_id = t.id and has_location(ml.location_id)))) then
    raise exception 'You can''t invite this person.';
  end if;
  delete from invites where member_id = t.id and used_at is null;
  insert into invites (org_id, member_id, created_by) values (t.org_id, t.id, auth.uid()) returning token into tok;
  return tok;
end $$;

-- Accept an invite: links the signed-in login to that person. Also used to move someone to a new phone.
create or replace function public.accept_invite(tok text)
  returns json language plpgsql security definer set search_path = public as
$$ declare i invites%rowtype; t members%rowtype; begin
  if auth.uid() is null then raise exception 'Sign in first.'; end if;
  -- a link keeps working for 24 hours after it is first opened (so a phone can join again from its Home Screen app)
  select * into i from invites where token = tok and expires_at > now()
    and (used_at is null or used_at > now() - interval '24 hours');
  if not found then raise exception 'This invite link has expired or was already used. Ask for a new one.'; end if;
  select * into t from members where id = i.member_id;
  if not t.active then raise exception 'This person has been switched off.'; end if;
  if exists (select 1 from members where user_id = auth.uid() and id <> t.id) then
    raise exception 'This login already belongs to someone else.';
  end if;
  update members set user_id = auth.uid() where id = t.id;
  update invites set used_at = coalesce(used_at, now()) where token = tok;
  return json_build_object('member_id', t.id, 'org_id', t.org_id, 'role', t.role, 'name', t.name);
end $$;

-- Add a person with their role and locations, and return their invite link token.
-- Admins can add anyone; bookkeepers can add staff to their own locations.
create or replace function public.add_person(p_name text, p_role text, p_email text, p_locations uuid[])
  returns json language plpgsql security definer set search_path = public as
$$ declare m uuid; loc uuid; tok text; begin
  if my_role() is null or my_role() not in ('admin','bookkeeper') then raise exception 'Only admins and bookkeepers can add people.'; end if;
  if p_role not in ('admin','bookkeeper','staff','viewer') then raise exception 'Unknown role.'; end if;
  if my_role() = 'bookkeeper' and p_role <> 'staff' then raise exception 'Bookkeepers can only add staff.'; end if;
  if coalesce(array_length(p_locations,1),0) = 0 and p_role <> 'admin' then raise exception 'Pick at least one location.'; end if;
  foreach loc in array coalesce(p_locations, '{}') loop
    if not exists (select 1 from locations where id = loc and org_id = my_org()) then raise exception 'Unknown location.'; end if;
    if my_role() = 'bookkeeper' and not has_location(loc) then raise exception 'You can only add staff to your own locations.'; end if;
  end loop;
  insert into members (org_id, name, email, role) values (my_org(), trim(p_name), nullif(trim(p_email),''), p_role) returning id into m;
  insert into member_locations select m, unnest(coalesce(p_locations, '{}'));
  insert into invites (org_id, member_id, created_by) values (my_org(), m, auth.uid()) returning token into tok;
  return json_build_object('member_id', m, 'token', tok);
end $$;

-- Change a person's name, role, locations or switch them off/on.
create or replace function public.update_person(mid uuid, p_name text, p_role text, p_email text, p_active boolean, p_locations uuid[])
  returns boolean language plpgsql security definer set search_path = public as
$$ declare t members%rowtype; loc uuid; begin
  select * into t from members where id = mid and org_id = my_org();
  if not found then raise exception 'Person not found.'; end if;
  if my_role() = 'admin' then null;
  elsif my_role() = 'bookkeeper' and t.role = 'staff' and p_role = 'staff' and member_in_my_locations(mid) then null;
  else raise exception 'You can''t change this person.'; end if;
  foreach loc in array coalesce(p_locations, '{}') loop
    if not exists (select 1 from locations where id = loc and org_id = my_org()) then raise exception 'Unknown location.'; end if;
    if my_role() = 'bookkeeper' and not has_location(loc) then raise exception 'You can only use your own locations.'; end if;
  end loop;
  update members set name = coalesce(nullif(trim(p_name),''), name), role = p_role, email = nullif(trim(p_email),''), active = p_active where id = mid;
  delete from member_locations where member_id = mid and (my_role() = 'admin' or has_location(location_id));
  insert into member_locations select mid, unnest(coalesce(p_locations, '{}')) on conflict do nothing;
  return true;
end $$;

-- Everything the app needs to start: me, my organisation, my locations, the people I can see.
create or replace function public.whoami()
  returns json language sql stable security definer set search_path = public as
$$ select json_build_object(
    'member', (select row_to_json(m) from members m where m.user_id = auth.uid() and m.active),
    'org', (select row_to_json(o) from orgs o where o.id = my_org()),
    'locations', coalesce((select json_agg(row_to_json(l) order by l.created_at) from locations l
                  where l.org_id = my_org() and (my_role() = 'admin' or has_location(l.id))), '[]'::json),
    'people', coalesce((select json_agg(json_build_object('id', m.id, 'name', m.name, 'email', m.email, 'role', m.role,
                  'active', m.active, 'joined', m.user_id is not null,
                  'locations', (select coalesce(json_agg(ml.location_id), '[]'::json) from member_locations ml where ml.member_id = m.id))
                  order by m.name) from members m
                  where m.org_id = my_org() and (my_role() = 'admin' or m.user_id = auth.uid()
                    or (my_role() in ('bookkeeper','viewer') and exists (select 1 from member_locations ml
                        where ml.member_id = m.id and has_location(ml.location_id))))), '[]'::json)) $$;

-- ---------- access for signed-in users (row level security above decides what they can see) ----------
grant usage on schema public to authenticated;
grant select, insert, update on public.orgs, public.locations, public.members, public.records to authenticated;
grant select, insert, delete on public.member_locations to authenticated;
grant execute on function public.create_org(text,text,text), public.create_invite(uuid), public.accept_invite(text), public.whoami(),
  public.add_person(text,text,text,uuid[]), public.update_person(uuid,text,text,text,boolean,uuid[]) to authenticated;
revoke all on public.invites from anon, authenticated;
revoke all on public.orgs, public.locations, public.members, public.member_locations, public.records from anon;

-- ---------- receipt photos ----------
-- Stored as  <org>/<location>/<person>/<file>.jpg  in a private bucket.
insert into storage.buckets (id, name, public) values ('receipts', 'receipts', false) on conflict (id) do nothing;
drop policy if exists receipts_upload on storage.objects;
create policy receipts_upload on storage.objects for insert to authenticated with check (
  bucket_id = 'receipts' and (storage.foldername(name))[1] = my_org()::text
  and (can_book(((storage.foldername(name))[2])::uuid)
       or (my_role() = 'staff' and has_location(((storage.foldername(name))[2])::uuid)
           and (storage.foldername(name))[3] = my_member_id()::text)));
drop policy if exists receipts_read on storage.objects;
create policy receipts_read on storage.objects for select to authenticated using (
  bucket_id = 'receipts' and (storage.foldername(name))[1] = my_org()::text
  and (can_view(((storage.foldername(name))[2])::uuid) or (storage.foldername(name))[3] = my_member_id()::text));
