-- Supabase PostgreSQL schema reverse-engineered from the Trello feature and requirement matrix.
-- Assumes a fresh Supabase project. Auth identities stay in auth.users; secrets stay outside public tables.
begin;
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
grant usage on schema private to authenticated;

create type public.workspace_role as enum ('owner','admin','member');
create type public.board_role as enum ('admin','member','observer');
create type public.board_visibility as enum ('private','workspace','public');
create type public.date_mode as enum ('date_only','instant');
create type public.scan_state as enum ('pending','clean','quarantined','failed');
create type public.field_type as enum ('text','number','date','checkbox','dropdown','url');
create type public.job_state as enum ('queued','running','completed','failed','cancelled');
create type public.connection_state as enum ('active','needs_reconnect','revoked','error');

-- Identity is managed by Supabase Auth. Email/password/session data is never copied here.
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default '', avatar_path text,
  locale text not null default 'en' check (locale in ('en','th')),
  timezone text not null default 'UTC', created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create or replace function private.on_auth_user_created() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles(id,display_name) values (new.id,coalesce(new.raw_user_meta_data->>'display_name','')) on conflict do nothing;
  return new;
end;
$$;
create trigger auth_profile_created after insert on auth.users for each row execute function private.on_auth_user_created();

create table public.organizations (
  id uuid primary key default gen_random_uuid(), name text not null check (length(btrim(name)) between 1 and 160),
  status text not null default 'active' check (status in ('active','suspended','closed')),
  created_by uuid references auth.users(id) on delete set null, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.organization_members (
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade, role text not null check (role in ('owner','admin','member')),
  joined_at timestamptz not null default now(), primary key (organization_id,user_id)
);
create index organization_members_user_idx on public.organization_members(user_id,organization_id);
create table public.organization_policies (
  organization_id uuid primary key references public.organizations(id) on delete cascade,
  allowed_email_domains text[] not null default '{}', public_boards_allowed boolean not null default false,
  allowed_attachment_mimes text[] not null default '{}', external_connections_allowed boolean not null default true,
  data_boundary text, version bigint not null default 1, updated_by uuid references auth.users(id) on delete set null, updated_at timestamptz not null default now()
);

create table public.workspaces (
  id uuid primary key default gen_random_uuid(), organization_id uuid references public.organizations(id) on delete set null,
  name text not null check (length(btrim(name)) between 1 and 160), description text not null default '', avatar_path text,
  status text not null default 'active' check (status in ('active','closed','pending_deletion')),
  created_by uuid not null references auth.users(id) on delete restrict, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.workspace_members (
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade, role public.workspace_role not null default 'member',
  member_kind text not null default 'member' check (member_kind in ('member','guest')),
  invited_by uuid references auth.users(id) on delete set null, joined_at timestamptz not null default now(), primary key (workspace_id,user_id)
);
create index workspace_members_user_idx on public.workspace_members(user_id,workspace_id);

create table public.boards (
  id uuid primary key default gen_random_uuid(), workspace_id uuid not null references public.workspaces(id) on delete cascade,
  name text not null check (length(btrim(name)) between 1 and 160), description text not null default '',
  visibility public.board_visibility not null default 'private', background jsonb not null default '{"kind":"color","value":"#f7f8fb"}',
  allow_observer_comments boolean not null default true, members_can_invite boolean not null default false,
  closed_at timestamptz, created_by uuid not null references auth.users(id) on delete restrict,
  version bigint not null default 1 check (version>0), created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique(id,workspace_id)
);
create index boards_workspace_idx on public.boards(workspace_id,closed_at,name);
create table public.board_members (
  board_id uuid not null references public.boards(id) on delete cascade, user_id uuid not null references auth.users(id) on delete cascade,
  role public.board_role not null default 'member', invited_by uuid references auth.users(id) on delete set null,
  joined_at timestamptz not null default now(), primary key(board_id,user_id)
);
create index board_members_user_idx on public.board_members(user_id,board_id);
create table public.user_board_preferences (
  user_id uuid not null references auth.users(id) on delete cascade,
  board_id uuid not null references public.boards(id) on delete cascade,
  is_starred boolean not null default false, last_opened_at timestamptz,
  primary key(user_id,board_id)
);
create index user_board_preferences_recent_idx on public.user_board_preferences(user_id,last_opened_at desc);
create table public.invitations (
  id uuid primary key default gen_random_uuid(), scope text not null check (scope in ('workspace','board')),
  workspace_id uuid references public.workspaces(id) on delete cascade, board_id uuid references public.boards(id) on delete cascade,
  email_normalized text not null, workspace_role public.workspace_role, board_role public.board_role,
  token_hash text not null unique, expires_at timestamptz not null, accepted_at timestamptz, revoked_at timestamptz,
  created_by uuid not null references auth.users(id) on delete restrict, created_at timestamptz not null default now(),
  check ((scope='workspace' and workspace_id is not null and board_id is null and workspace_role is not null and board_role is null)
      or (scope='board' and board_id is not null and workspace_id is null and board_role is not null and workspace_role is null))
);
create index invitations_workspace_idx on public.invitations(workspace_id,expires_at) where revoked_at is null and accepted_at is null;
create index invitations_board_idx on public.invitations(board_id,expires_at) where revoked_at is null and accepted_at is null;

create table public.board_collections (
  id uuid primary key default gen_random_uuid(), workspace_id uuid not null references public.workspaces(id) on delete cascade,
  name text not null check (length(btrim(name)) between 1 and 120), position numeric(20,6) not null default 0,
  created_by uuid not null references auth.users(id) on delete restrict, unique(workspace_id,name)
);
create table public.collection_boards (
  collection_id uuid not null references public.board_collections(id) on delete cascade,
  board_id uuid not null references public.boards(id) on delete cascade, position numeric(20,6) not null default 0,
  primary key(collection_id,board_id)
);
create table public.lists (
  id uuid primary key default gen_random_uuid(), board_id uuid not null references public.boards(id) on delete cascade,
  title text not null check (length(btrim(title)) between 1 and 160), position numeric(20,6) not null default 0,
  color text, is_collapsed boolean not null default false, archived_at timestamptz,
  created_by uuid not null references auth.users(id) on delete restrict, version bigint not null default 1 check(version>0),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique(id,board_id)
);
create index lists_board_position_idx on public.lists(board_id,archived_at,position);
create table public.cards (
  id uuid primary key default gen_random_uuid(), board_id uuid not null references public.boards(id) on delete cascade,
  list_id uuid not null, title text not null check(length(btrim(title)) between 1 and 500), description text not null default '',
  position numeric(20,6) not null default 0, priority smallint check(priority between 0 and 4),
  is_complete boolean not null default false, completed_at timestamptz, archived_at timestamptz,
  cover jsonb, created_by uuid not null references auth.users(id) on delete restrict,
  version bigint not null default 1 check(version>0), created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  foreign key(list_id,board_id) references public.lists(id,board_id) on delete cascade, unique(id,board_id)
);
create index cards_board_list_position_idx on public.cards(board_id,list_id,archived_at,position);
create index cards_list_complete_idx on public.cards(list_id,is_complete) where archived_at is null;
create index cards_search_idx on public.cards using gin(to_tsvector('simple',coalesce(title,'')||' '||coalesce(description,'')));
create table public.card_members (
  card_id uuid not null references public.cards(id) on delete cascade, user_id uuid not null references auth.users(id) on delete cascade,
  assigned_by uuid references auth.users(id) on delete set null, assigned_at timestamptz not null default now(), primary key(card_id,user_id)
);
create index card_members_user_idx on public.card_members(user_id,card_id);
create table public.labels (
  id uuid primary key default gen_random_uuid(), board_id uuid not null references public.boards(id) on delete cascade,
  name text not null check(length(btrim(name)) between 1 and 80), color text not null default '#8b83e8',
  created_by uuid references auth.users(id) on delete set null, created_at timestamptz not null default now(), unique(board_id,name), unique(id,board_id)
);
create table public.card_labels (
  card_id uuid not null, label_id uuid not null, board_id uuid not null, added_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(), primary key(card_id,label_id),
  foreign key(card_id,board_id) references public.cards(id,board_id) on delete cascade,
  foreign key(label_id,board_id) references public.labels(id,board_id) on delete cascade
);
create index card_labels_label_idx on public.card_labels(label_id,card_id);
create table public.card_dates (
  card_id uuid primary key references public.cards(id) on delete cascade, start_date date, due_date date, due_at timestamptz,
  mode public.date_mode not null default 'date_only', timezone text not null default 'UTC', reminder_at timestamptz,
  updated_by uuid references auth.users(id) on delete set null, updated_at timestamptz not null default now(),
  check((mode='date_only' and due_at is null) or (mode='instant' and due_date is null))
);
create index card_dates_due_date_idx on public.card_dates(due_date) where due_date is not null;
create index card_dates_due_at_idx on public.card_dates(due_at) where due_at is not null;
create index card_dates_reminder_idx on public.card_dates(reminder_at) where reminder_at is not null;
create table public.recurrence_rules (
  id uuid primary key default gen_random_uuid(), card_id uuid not null unique references public.cards(id) on delete cascade,
  cadence text not null check(cadence in ('daily','weekly','monthly','yearly','custom')), interval_count integer not null default 1 check(interval_count>0),
  weekdays smallint[] not null default '{}', month_day smallint check(month_day between 1 and 31), timezone text not null default 'UTC',
  next_occurrence_at timestamptz, last_occurrence_key text, enabled boolean not null default true,
  created_by uuid references auth.users(id) on delete set null, created_at timestamptz not null default now()
);

create table public.checklists (
  id uuid primary key default gen_random_uuid(), card_id uuid not null references public.cards(id) on delete cascade,
  title text not null check(length(btrim(title)) between 1 and 160), position numeric(20,6) not null default 0,
  created_by uuid not null references auth.users(id) on delete restrict, created_at timestamptz not null default now(), unique(id,card_id)
);
create index checklists_card_position_idx on public.checklists(card_id,position);
create table public.checklist_items (
  id uuid primary key default gen_random_uuid(), checklist_id uuid not null references public.checklists(id) on delete cascade,
  title text not null check(length(btrim(title)) between 1 and 500), position numeric(20,6) not null default 0,
  is_complete boolean not null default false, completed_by uuid references auth.users(id) on delete set null, completed_at timestamptz,
  assignee_id uuid references auth.users(id) on delete set null, due_at timestamptz, created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index checklist_items_position_idx on public.checklist_items(checklist_id,position);
create index checklist_items_assignee_due_idx on public.checklist_items(assignee_id,due_at) where is_complete=false;
create table public.comments (
  id uuid primary key default gen_random_uuid(), card_id uuid not null references public.cards(id) on delete cascade,
  author_id uuid references auth.users(id) on delete set null, body text not null check(length(btrim(body)) between 1 and 10000),
  edited_at timestamptz, deleted_at timestamptz, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index comments_card_time_idx on public.comments(card_id,created_at desc) where deleted_at is null;
create table public.comment_revisions (
  id uuid primary key default gen_random_uuid(), comment_id uuid not null references public.comments(id) on delete cascade,
  editor_id uuid references auth.users(id) on delete set null, body_snapshot text not null, created_at timestamptz not null default now()
);
create table public.attachments (
  id uuid primary key default gen_random_uuid(), card_id uuid references public.cards(id) on delete cascade,
  inbox_item_id uuid, uploaded_by uuid references auth.users(id) on delete set null,
  bucket_id text not null default 'orbit-attachments', object_path text, source_url text, file_name text not null,
  mime_type text, size_bytes bigint check(size_bytes is null or size_bytes>=0), scan_status public.scan_state not null default 'pending',
  scan_completed_at timestamptz, deleted_at timestamptz, created_at timestamptz not null default now(),
  check((card_id is not null) <> (inbox_item_id is not null)), check((object_path is not null) <> (source_url is not null)), unique(bucket_id,object_path)
);
create index attachments_card_idx on public.attachments(card_id,created_at) where deleted_at is null;

create table public.card_mirrors (
  id uuid primary key default gen_random_uuid(), source_card_id uuid not null references public.cards(id) on delete cascade,
  destination_board_id uuid not null references public.boards(id) on delete cascade, destination_list_id uuid not null references public.lists(id) on delete cascade,
  position numeric(20,6) not null default 0, created_by uuid not null references auth.users(id) on delete restrict, created_at timestamptz not null default now(),
  unique(source_card_id,destination_board_id,destination_list_id)
);
create index card_mirrors_destination_idx on public.card_mirrors(destination_board_id,destination_list_id,position);
create table public.field_definitions (
  id uuid primary key default gen_random_uuid(), board_id uuid not null references public.boards(id) on delete cascade,
  name text not null check(length(btrim(name)) between 1 and 100), field_type public.field_type not null,
  options jsonb not null default '[]', position numeric(20,6) not null default 0, show_on_card boolean not null default false,
  created_by uuid not null references auth.users(id) on delete restrict, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique(board_id,name), unique(id,board_id)
);
create table public.card_field_values (
  card_id uuid not null, field_id uuid not null, board_id uuid not null, value jsonb,
  updated_by uuid references auth.users(id) on delete set null, updated_at timestamptz not null default now(), primary key(card_id,field_id),
  foreign key(card_id,board_id) references public.cards(id,board_id) on delete cascade,
  foreign key(field_id,board_id) references public.field_definitions(id,board_id) on delete cascade
);
create index card_field_value_lookup_idx on public.card_field_values(field_id,value);

create table public.inbox_items (
  id uuid primary key default gen_random_uuid(), owner_id uuid not null references auth.users(id) on delete cascade,
  title text not null check(length(btrim(title)) between 1 and 500), body text not null default '', source text not null default 'manual', source_url text,
  state text not null default 'open' check(state in ('open','converted','archived')), converted_card_id uuid references public.cards(id) on delete set null,
  version bigint not null default 1, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index inbox_owner_state_idx on public.inbox_items(owner_id,state,updated_at desc);
alter table public.attachments add constraint attachments_inbox_fk foreign key(inbox_item_id) references public.inbox_items(id) on delete cascade;
create table public.saved_searches (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade,
  name text not null, query jsonb not null, created_at timestamptz not null default now(), unique(user_id,name)
);
create table public.saved_views (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade,
  board_id uuid references public.boards(id) on delete cascade, name text not null,
  view_type text not null check(view_type in ('board','table','calendar','timeline','dashboard','map')),
  configuration jsonb not null default '{}', is_shared boolean not null default false, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.notification_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade, in_app_enabled boolean not null default true,
  email_enabled boolean not null default true, push_enabled boolean not null default false,
  digest_frequency text not null default 'off' check(digest_frequency in ('off','daily','weekly')), updated_at timestamptz not null default now()
);
create table public.notifications (
  id uuid primary key default gen_random_uuid(), recipient_id uuid not null references auth.users(id) on delete cascade,
  event_key text not null, channel text not null default 'in_app' check(channel in ('in_app','email','push')),
  target_type text not null check(target_type in ('workspace','board','card','comment','checklist_item','inbox_item')),
  target_id uuid not null, actor_id uuid references auth.users(id) on delete set null, title text not null, body text not null default '',
  read_at timestamptz, created_at timestamptz not null default now(), unique(event_key,recipient_id,channel)
);
create index notifications_unread_idx on public.notifications(recipient_id,created_at desc) where read_at is null;
create table public.watch_subscriptions (
  user_id uuid not null references auth.users(id) on delete cascade, target_type text not null check(target_type in ('board','list','card')),
  target_id uuid not null, created_at timestamptz not null default now(), primary key(user_id,target_type,target_id)
);

create table public.calendar_connections (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade,
  provider text not null, provider_account_id text not null, encrypted_secret_ref text not null, scopes text[] not null default '{}',
  status public.connection_state not null default 'active', last_synced_at timestamptz, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique(user_id,provider,provider_account_id)
);
create table public.focus_blocks (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade,
  card_id uuid references public.cards(id) on delete set null, calendar_connection_id uuid references public.calendar_connections(id) on delete set null,
  provider_event_id text, title text not null, starts_at timestamptz not null, ends_at timestamptz not null, timezone text not null default 'UTC',
  status text not null default 'active' check(status in ('active','cancelled','sync_error')), created_at timestamptz not null default now(),
  check(ends_at>starts_at)
);
create index focus_blocks_user_start_idx on public.focus_blocks(user_id,starts_at);

create table public.templates (
  id uuid primary key default gen_random_uuid(), workspace_id uuid references public.workspaces(id) on delete cascade,
  template_type text not null check(template_type in ('card','board')), name text not null, description text not null default '',
  definition jsonb not null, version integer not null default 1, is_published boolean not null default false,
  created_by uuid not null references auth.users(id) on delete restrict, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.automation_rules (
  id uuid primary key default gen_random_uuid(), workspace_id uuid references public.workspaces(id) on delete cascade,
  board_id uuid references public.boards(id) on delete cascade, name text not null, trigger_definition jsonb not null,
  condition_definition jsonb not null default '[]', action_definition jsonb not null, status text not null default 'paused' check(status in ('active','paused','disabled')),
  service_actor_scopes text[] not null default '{}', max_depth smallint not null default 3 check(max_depth between 1 and 10),
  hourly_limit integer not null default 100 check(hourly_limit>0), created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  check((workspace_id is not null) <> (board_id is not null))
);
create index automation_rules_board_idx on public.automation_rules(board_id,status) where board_id is not null;
create index automation_rules_workspace_idx on public.automation_rules(workspace_id,status) where workspace_id is not null;
create table public.automation_runs (
  id uuid primary key default gen_random_uuid(), rule_id uuid not null references public.automation_rules(id) on delete cascade,
  occurrence_key text not null, status text not null default 'queued' check(status in ('queued','running','succeeded','failed','skipped','cancelled')),
  origin_chain uuid[] not null default '{}', result_summary jsonb not null default '{}', error_code text,
  correlation_id uuid not null default gen_random_uuid(), started_at timestamptz, finished_at timestamptz,
  created_at timestamptz not null default now(), unique(rule_id,occurrence_key)
);
create index automation_runs_rule_time_idx on public.automation_runs(rule_id,created_at desc);
create table public.integration_connections (
  id uuid primary key default gen_random_uuid(), workspace_id uuid references public.workspaces(id) on delete cascade,
  user_id uuid references auth.users(id) on delete cascade, provider text not null, provider_account_id text,
  encrypted_secret_ref text not null, scopes text[] not null default '{}', status public.connection_state not null default 'active',
  installed_by uuid references auth.users(id) on delete set null, checked_at timestamptz, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  check((workspace_id is not null) <> (user_id is not null))
);
create index integration_workspace_idx on public.integration_connections(workspace_id,status);
create index integration_user_idx on public.integration_connections(user_id,status);
create table public.api_credentials (
  id uuid primary key default gen_random_uuid(), owner_id uuid not null references auth.users(id) on delete cascade,
  workspace_id uuid references public.workspaces(id) on delete cascade, name text not null, token_hash text not null unique,
  scopes text[] not null default '{}', expires_at timestamptz, revoked_at timestamptz, created_at timestamptz not null default now()
);
create table public.webhooks (
  id uuid primary key default gen_random_uuid(), workspace_id uuid not null references public.workspaces(id) on delete cascade,
  endpoint_url text not null, encrypted_secret_ref text not null, event_types text[] not null,
  status text not null default 'active' check(status in ('active','paused','revoked')),
  created_by uuid not null references auth.users(id) on delete restrict, created_at timestamptz not null default now()
);
create table public.webhook_deliveries (
  id uuid primary key default gen_random_uuid(), webhook_id uuid not null references public.webhooks(id) on delete cascade,
  event_id uuid not null, attempt integer not null default 1 check(attempt>0), response_status integer, response_excerpt text,
  delivered_at timestamptz, retry_at timestamptz, created_at timestamptz not null default now(), unique(webhook_id,event_id,attempt)
);
create index webhook_retry_idx on public.webhook_deliveries(retry_at) where delivered_at is null;

create table public.activity_events (
  id uuid primary key default gen_random_uuid(), board_id uuid not null references public.boards(id) on delete cascade,
  card_id uuid references public.cards(id) on delete set null, actor_id uuid references auth.users(id) on delete set null,
  action text not null, target_type text not null, target_id uuid not null, details jsonb not null default '{}',
  occurred_at timestamptz not null default now(), correlation_id uuid
);
create index activity_board_time_idx on public.activity_events(board_id,occurred_at desc);
create table public.audit_events (
  id uuid primary key default gen_random_uuid(), organization_id uuid references public.organizations(id) on delete set null,
  workspace_id uuid references public.workspaces(id) on delete set null, board_id uuid references public.boards(id) on delete set null,
  actor_id uuid references auth.users(id) on delete set null, action text not null, target_type text not null, target_id uuid,
  before_state jsonb, after_state jsonb, reason text, occurred_at timestamptz not null default now(), correlation_id uuid not null default gen_random_uuid()
);
create index audit_workspace_time_idx on public.audit_events(workspace_id,occurred_at desc);
create table public.outbox_events (
  id uuid primary key default gen_random_uuid(), event_type text not null, aggregate_type text not null, aggregate_id uuid not null,
  payload jsonb not null, occurred_at timestamptz not null default now(), published_at timestamptz,
  attempts integer not null default 0, correlation_id uuid not null default gen_random_uuid()
);
create index outbox_unpublished_idx on public.outbox_events(occurred_at) where published_at is null;

-- Transactional activity/outbox records are committed with the underlying card/comment mutation.
create or replace function private.record_card_event() returns trigger
language plpgsql security definer set search_path = '' as $$
declare v_action text; v_details jsonb;
begin
  if tg_op='INSERT' then
    v_action:='card.created'; v_details:=jsonb_build_object('list_id',new.list_id);
  elsif tg_op='UPDATE' then
    if old.list_id is distinct from new.list_id then v_action:='card.moved'; v_details:=jsonb_build_object('from_list_id',old.list_id,'to_list_id',new.list_id);
    elsif old.is_complete is distinct from new.is_complete then v_action:=case when new.is_complete then 'card.completed' else 'card.reopened' end; v_details:='{}'::jsonb;
    elsif old.archived_at is distinct from new.archived_at then v_action:=case when new.archived_at is null then 'card.restored' else 'card.archived' end; v_details:='{}'::jsonb;
    else v_action:='card.updated'; v_details:='{}'::jsonb; end if;
  else return new; end if;
  insert into public.activity_events(board_id,card_id,actor_id,action,target_type,target_id,details)
  values(new.board_id,new.id,(select auth.uid()),v_action,'card',new.id,v_details);
  insert into public.outbox_events(event_type,aggregate_type,aggregate_id,payload)
  values(v_action,'card',new.id,jsonb_build_object('board_id',new.board_id,'card_id',new.id,'action',v_action,'details',v_details));
  return new;
end; $$;
create trigger cards_activity_outbox after insert or update on public.cards for each row execute function private.record_card_event();

create or replace function private.record_comment_event() returns trigger
language plpgsql security definer set search_path = '' as $$
declare v_board uuid;
begin
  v_board:=private.card_board_id(new.card_id);
  insert into public.activity_events(board_id,card_id,actor_id,action,target_type,target_id,details)
  values(v_board,new.card_id,new.author_id,'comment.created','comment',new.id,'{}'::jsonb);
  insert into public.outbox_events(event_type,aggregate_type,aggregate_id,payload)
  values('comment.created','comment',new.id,jsonb_build_object('board_id',v_board,'card_id',new.card_id,'comment_id',new.id));
  return new;
end; $$;
create trigger comments_activity_outbox after insert on public.comments for each row execute function private.record_comment_event();

create or replace function private.retain_comment_revision() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if old.body is distinct from new.body then
    insert into public.comment_revisions(comment_id,editor_id,body_snapshot) values(old.id,(select auth.uid()),old.body);
    new.edited_at:=now();
  end if;
  return new;
end; $$;
create trigger comments_revision before update on public.comments for each row execute function private.retain_comment_revision();

create or replace function private.audit_workspace_member_change() returns trigger
language plpgsql security definer set search_path = '' as $$
declare wid uuid; uid uuid; v_action text; v_before jsonb; v_after jsonb;
begin
  if tg_op='DELETE' then wid:=old.workspace_id; uid:=old.user_id; v_before:=to_jsonb(old); v_after:=null; v_action:='workspace.member.removed';
  elsif tg_op='INSERT' then wid:=new.workspace_id; uid:=new.user_id; v_before:=null; v_after:=to_jsonb(new); v_action:='workspace.member.added';
  else wid:=new.workspace_id; uid:=new.user_id; v_before:=to_jsonb(old); v_after:=to_jsonb(new); v_action:='workspace.member.changed'; end if;
  insert into public.audit_events(workspace_id,actor_id,action,target_type,target_id,before_state,after_state)
  values(wid,(select auth.uid()),v_action,'workspace_member',uid,v_before,v_after);
  if tg_op='DELETE' then return old; else return new; end if;
end; $$;
create trigger workspace_members_audit after insert or update or delete on public.workspace_members
for each row execute function private.audit_workspace_member_change();

create or replace function private.audit_board_member_change() returns trigger
language plpgsql security definer set search_path = '' as $$
declare bid uuid; uid uuid; wid uuid; v_action text; v_before jsonb; v_after jsonb;
begin
  if tg_op='DELETE' then bid:=old.board_id; uid:=old.user_id; v_before:=to_jsonb(old); v_after:=null; v_action:='board.member.removed';
  elsif tg_op='INSERT' then bid:=new.board_id; uid:=new.user_id; v_before:=null; v_after:=to_jsonb(new); v_action:='board.member.added';
  else bid:=new.board_id; uid:=new.user_id; v_before:=to_jsonb(old); v_after:=to_jsonb(new); v_action:='board.member.changed'; end if;
  select b.workspace_id into wid from public.boards b where b.id=bid;
  insert into public.audit_events(workspace_id,board_id,actor_id,action,target_type,target_id,before_state,after_state)
  values(wid,bid,(select auth.uid()),v_action,'board_member',uid,v_before,v_after);
  if tg_op='DELETE' then return old; else return new; end if;
end; $$;
create trigger board_members_audit after insert or update or delete on public.board_members
for each row execute function private.audit_board_member_change();

create table public.import_export_jobs (
  id uuid primary key default gen_random_uuid(), workspace_id uuid references public.workspaces(id) on delete cascade,
  board_id uuid references public.boards(id) on delete cascade, owner_id uuid not null references auth.users(id) on delete cascade,
  kind text not null check(kind in ('import_json','import_csv','trello_migration','export_json','export_csv','workspace_export','print')),
  status public.job_state not null default 'queued', dry_run boolean not null default true, source_name text,
  mapping jsonb not null default '{}', manifest jsonb not null default '{}', errors jsonb not null default '[]',
  result_path text, result_expires_at timestamptz, created_at timestamptz not null default now(), started_at timestamptz, finished_at timestamptz,
  check((workspace_id is null) <> (board_id is null))
);
create index jobs_owner_idx on public.import_export_jobs(owner_id,created_at desc);
create table public.external_id_maps (
  id uuid primary key default gen_random_uuid(), job_id uuid not null references public.import_export_jobs(id) on delete cascade,
  external_system text not null, external_id text not null, local_type text not null, local_id uuid not null,
  created_at timestamptz not null default now(), unique(job_id,external_system,external_id)
);

create table public.billing_plans (
  id uuid primary key default gen_random_uuid(), code text not null unique, name text not null, entitlements jsonb not null default '{}', active boolean not null default true
);
create table public.subscriptions (
  id uuid primary key default gen_random_uuid(), workspace_id uuid not null unique references public.workspaces(id) on delete cascade,
  plan_id uuid not null references public.billing_plans(id) on delete restrict,
  status text not null default 'trialing' check(status in ('trialing','active','past_due','cancel_at_period_end','cancelled','expired')),
  provider_customer_id text, provider_subscription_id text unique, period_start timestamptz, period_end timestamptz, cancel_at timestamptz,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.invoices (
  id uuid primary key default gen_random_uuid(), workspace_id uuid not null references public.workspaces(id) on delete cascade,
  provider_invoice_id text unique, amount_minor bigint not null check(amount_minor>=0), currency char(3) not null,
  status text not null, issued_at timestamptz, paid_at timestamptz, provider_event jsonb not null default '{}', created_at timestamptz not null default now()
);
create table public.usage_records (
  id uuid primary key default gen_random_uuid(), workspace_id uuid not null references public.workspaces(id) on delete cascade,
  metric text not null, period_start date not null, quantity bigint not null default 0 check(quantity>=0), created_at timestamptz not null default now(),
  unique(workspace_id,metric,period_start)
);
create table public.ai_requests (
  id uuid primary key default gen_random_uuid(), workspace_id uuid not null references public.workspaces(id) on delete cascade,
  board_id uuid references public.boards(id) on delete cascade, requested_by uuid not null references auth.users(id) on delete restrict,
  action text not null, provider text, prompt_version text, cost_minor bigint check(cost_minor is null or cost_minor>=0),
  status text not null default 'draft' check(status in ('draft','applied','cancelled','failed')),
  created_at timestamptz not null default now(), completed_at timestamptz
);
create table public.ai_drafts (
  id uuid primary key default gen_random_uuid(), request_id uuid not null unique references public.ai_requests(id) on delete cascade,
  draft_content jsonb not null, source_versions jsonb not null default '{}', applied_at timestamptz, cancelled_at timestamptz, created_at timestamptz not null default now()
);
create table public.merge_operations (
  id uuid primary key default gen_random_uuid(), board_id uuid not null references public.boards(id) on delete cascade,
  created_by uuid not null references auth.users(id) on delete restrict, result_card_id uuid references public.cards(id) on delete set null,
  source_card_ids uuid[] not null, source_versions jsonb not null, status text not null default 'draft' check(status in ('draft','applied','cancelled')),
  created_at timestamptz not null default now(), applied_at timestamptz
);
create table public.workflow_policies (
  board_id uuid primary key references public.boards(id) on delete cascade, wip_limits jsonb not null default '{}',
  approvals jsonb not null default '{}', time_tracking_enabled boolean not null default false,
  updated_by uuid references auth.users(id) on delete set null, updated_at timestamptz not null default now()
);
create table public.card_dependencies (
  predecessor_card_id uuid not null references public.cards(id) on delete cascade,
  successor_card_id uuid not null references public.cards(id) on delete cascade,
  dependency_type text not null default 'blocks' check(dependency_type in ('blocks','relates_to')),
  created_by uuid references auth.users(id) on delete set null, created_at timestamptz not null default now(),
  primary key(predecessor_card_id,successor_card_id), check(predecessor_card_id<>successor_card_id)
);
create table public.time_entries (
  id uuid primary key default gen_random_uuid(), card_id uuid not null references public.cards(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade, started_at timestamptz not null, ended_at timestamptz,
  estimate_minutes integer check(estimate_minutes is null or estimate_minutes>=0), note text not null default '', created_at timestamptz not null default now(),
  check(ended_at is null or ended_at>started_at)
);
create index time_entries_card_user_idx on public.time_entries(card_id,user_id,started_at desc);

-- Atomic default memberships on workspace/board creation.
create or replace function private.add_workspace_owner() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.workspace_members(workspace_id,user_id,role) values(new.id,new.created_by,'owner');
  return new;
end;
$$;
create trigger workspace_owner_after_insert after insert on public.workspaces for each row execute function private.add_workspace_owner();
create or replace function private.add_board_creator() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.board_members(board_id,user_id,role) values(new.id,new.created_by,'admin');
  return new;
end;
$$;
create trigger board_admin_after_insert after insert on public.boards for each row execute function private.add_board_creator();
create or replace function private.keep_workspace_owner() returns trigger
language plpgsql security definer set search_path = '' as $$
declare n integer;
begin
  if tg_op='DELETE' then
    if old.role<>'owner' then return old; end if;
    perform 1 from public.workspaces w where w.id=old.workspace_id for update;
    select count(*) into n from public.workspace_members m where m.workspace_id=old.workspace_id and m.role='owner';
    if n<=1 then raise exception 'workspace must keep at least one owner' using errcode='23514'; end if;
    return old;
  end if;
  if old.role='owner' and new.role<>'owner' then
    perform 1 from public.workspaces w where w.id=old.workspace_id for update;
    select count(*) into n from public.workspace_members m where m.workspace_id=old.workspace_id and m.role='owner';
    if n<=1 then raise exception 'workspace must keep at least one owner' using errcode='23514'; end if;
  end if;
  return new;
end; $$;
create trigger workspace_owner_guard before update or delete on public.workspace_members for each row execute function private.keep_workspace_owner();
create or replace function private.keep_board_admin() returns trigger
language plpgsql security definer set search_path = '' as $$
declare n integer;
begin
  if tg_op='DELETE' then
    if old.role<>'admin' then return old; end if;
    perform 1 from public.boards b where b.id=old.board_id for update;
    select count(*) into n from public.board_members m where m.board_id=old.board_id and m.role='admin';
    if n<=1 then raise exception 'board must keep at least one admin' using errcode='23514'; end if;
    return old;
  end if;
  if old.role='admin' and new.role<>'admin' then
    perform 1 from public.boards b where b.id=old.board_id for update;
    select count(*) into n from public.board_members m where m.board_id=old.board_id and m.role='admin';
    if n<=1 then raise exception 'board must keep at least one admin' using errcode='23514'; end if;
  end if;
  return new;
end; $$;
create trigger board_admin_guard before update or delete on public.board_members for each row execute function private.keep_board_admin();

-- RLS predicates. These SECURITY DEFINER helpers use fixed search_path to avoid recursive RLS checks.
create or replace function private.is_workspace_member(p_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
select exists(select 1 from public.workspace_members m where m.workspace_id=p_id and m.user_id=(select auth.uid())) $$;
create or replace function private.has_workspace_role(p_id uuid,p_roles text[]) returns boolean
language sql stable security definer set search_path = '' as $$
select exists(select 1 from public.workspace_members m where m.workspace_id=p_id and m.user_id=(select auth.uid()) and m.role::text=any(p_roles)) $$;
create or replace function private.has_org_role(p_id uuid,p_roles text[]) returns boolean
language sql stable security definer set search_path = '' as $$
select exists(select 1 from public.organization_members m where m.organization_id=p_id and m.user_id=(select auth.uid()) and m.role=any(p_roles)) $$;
create or replace function private.can_access_board(p_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
select exists(select 1 from public.boards b where b.id=p_id and (
  exists(select 1 from public.board_members bm where bm.board_id=b.id and bm.user_id=(select auth.uid())) or
  (b.visibility='workspace' and exists(select 1 from public.workspace_members wm where wm.workspace_id=b.workspace_id and wm.user_id=(select auth.uid()))))) $$;
create or replace function private.can_edit_board(p_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
select exists(select 1 from public.boards b join public.board_members m on m.board_id=b.id where b.id=p_id and b.closed_at is null and m.user_id=(select auth.uid()) and m.role in ('admin','member')) $$;
create or replace function private.can_admin_board(p_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
select exists(select 1 from public.board_members m join public.boards b on b.id=m.board_id where m.board_id=p_id and m.user_id=(select auth.uid()) and m.role='admin') $$;
create or replace function private.can_comment_board(p_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
select exists(select 1 from public.boards b where b.id=p_id and b.closed_at is null and private.can_access_board(b.id) and (
  exists(select 1 from public.board_members m where m.board_id=b.id and m.user_id=(select auth.uid()) and m.role in ('admin','member')) or
  (b.allow_observer_comments and exists(select 1 from public.board_members m where m.board_id=b.id and m.user_id=(select auth.uid()) and m.role='observer')))) $$;
create or replace function private.card_board_id(p_id uuid) returns uuid
language sql stable security definer set search_path = '' as $$ select c.board_id from public.cards c where c.id=p_id $$;
create or replace function private.can_view_card(p_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$ select private.can_access_board(private.card_board_id(p_id)) $$;
create or replace function private.can_edit_card(p_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$ select private.can_edit_board(private.card_board_id(p_id)) $$;
create or replace function private.can_comment_card(p_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$ select private.can_comment_board(private.card_board_id(p_id)) $$;
create or replace function private.board_for_list(p_id uuid) returns uuid
language sql stable security definer set search_path = '' as $$ select l.board_id from public.lists l where l.id=p_id $$;
create or replace function private.can_view_profile(p_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
select p_id=(select auth.uid()) or exists(select 1 from public.workspace_members a join public.workspace_members b on b.workspace_id=a.workspace_id where a.user_id=(select auth.uid()) and b.user_id=p_id)
or exists(select 1 from public.board_members a join public.board_members b on b.board_id=a.board_id where a.user_id=(select auth.uid()) and b.user_id=p_id) $$;
create or replace function private.can_access_notification_target(p_type text,p_id uuid) returns boolean
language plpgsql stable security definer set search_path = '' as $$
declare v_card uuid;
begin
  if p_type='workspace' then return private.is_workspace_member(p_id); end if;
  if p_type='board' then return private.can_access_board(p_id); end if;
  if p_type='card' then return private.can_view_card(p_id); end if;
  if p_type='comment' then select c.card_id into v_card from public.comments c where c.id=p_id; return private.can_view_card(v_card); end if;
  if p_type='checklist_item' then select cl.card_id into v_card from public.checklist_items i join public.checklists cl on cl.id=i.checklist_id where i.id=p_id; return private.can_view_card(v_card); end if;
  if p_type='inbox_item' then return exists(select 1 from public.inbox_items i where i.id=p_id and i.owner_id=(select auth.uid())); end if;
  return false;
end; $$;
create or replace function private.assert_board_assignee() returns trigger
language plpgsql security definer set search_path = '' as $$
declare v_card uuid; v_board uuid; v_user uuid;
begin
  if tg_table_name='card_members' then
    v_card:=new.card_id; v_user:=new.user_id;
  else
    v_user:=new.assignee_id;
    select c.card_id into v_card from public.checklists c where c.id=new.checklist_id;
  end if;
  if v_user is not null then
    v_board:=private.card_board_id(v_card);
    if not exists(select 1 from public.board_members m where m.board_id=v_board and m.user_id=v_user) then
      raise exception 'assignee must be a member of the Board' using errcode='23514';
    end if;
  end if;
  return new;
end; $$;
create trigger card_members_require_board_member before insert or update on public.card_members
for each row execute function private.assert_board_assignee();
create trigger checklist_items_require_board_member before insert or update on public.checklist_items
for each row execute function private.assert_board_assignee();
revoke all on all functions in schema private from public,anon;
grant execute on all functions in schema private to authenticated;
revoke all on function private.on_auth_user_created() from authenticated;
revoke all on function private.add_workspace_owner() from authenticated;
revoke all on function private.add_board_creator() from authenticated;

-- Version conflicts: update rows with both id and expected version; zero updated rows means reload/resolve.
create or replace function private.bump_version() returns trigger language plpgsql set search_path = '' as $$
begin new.version:=old.version+1; new.updated_at:=now(); return new; end; $$;
create trigger lists_version before update on public.lists for each row execute function private.bump_version();
create trigger cards_version before update on public.cards for each row execute function private.bump_version();
create or replace function private.touch_updated_at() returns trigger language plpgsql set search_path = '' as $$
begin new.updated_at:=now(); return new; end; $$;
create trigger profiles_touch before update on public.profiles for each row execute function private.touch_updated_at();
create trigger workspaces_touch before update on public.workspaces for each row execute function private.touch_updated_at();
create trigger saved_views_touch before update on public.saved_views for each row execute function private.touch_updated_at();

-- Prevent loss of the last Workspace owner or Board admin. Transfer ownership by first adding
-- the next owner/admin, then changing the previous member's role in the same trusted flow.
create or replace function private.protect_last_workspace_owner() returns trigger
language plpgsql security definer set search_path = '' as $$
declare n integer;
begin
  if old.role='owner' and (tg_op='DELETE' or new.role<>'owner') then
    select count(*) into n from public.workspace_members where workspace_id=old.workspace_id and role='owner';
    if n<=1 then raise exception 'workspace must retain at least one owner' using errcode='23514'; end if;
  end if;
  if tg_op='DELETE' then return old; else return new; end if;
end; $$;
create trigger protect_workspace_owner before update or delete on public.workspace_members
for each row execute function private.protect_last_workspace_owner();
create or replace function private.protect_last_board_admin() returns trigger
language plpgsql security definer set search_path = '' as $$
declare n integer;
begin
  if old.role='admin' and (tg_op='DELETE' or new.role<>'admin') then
    select count(*) into n from public.board_members where board_id=old.board_id and role='admin';
    if n<=1 then raise exception 'board must retain at least one admin' using errcode='23514'; end if;
  end if;
  if tg_op='DELETE' then return old; else return new; end if;
end; $$;
create trigger protect_board_admin before update or delete on public.board_members
for each row execute function private.protect_last_board_admin();
revoke all on function private.protect_last_workspace_owner() from public,anon,authenticated;
revoke all on function private.protect_last_board_admin() from public,anon,authenticated;

-- Default deny for client-facing tables. No anon privileges; tables without an explicit policy
-- below (audit writes, outbox, worker runs, provider secrets, billing mutations) stay server-only.
do $$ declare t record; begin
  for t in select tablename from pg_tables where schemaname='public' loop
    execute format('alter table public.%I enable row level security',t.tablename);
  end loop;
end $$;
revoke all on all tables in schema public from anon,authenticated;
grant select,insert,update,delete on all tables in schema public to authenticated;
revoke all on all sequences in schema public from anon,authenticated;

create policy profiles_select_shared on public.profiles for select to authenticated using (private.can_view_profile(id));
create policy profiles_update_self on public.profiles for update to authenticated using (id=(select auth.uid())) with check (id=(select auth.uid()));

create policy organizations_select_member on public.organizations for select to authenticated
using (private.has_org_role(id,array['owner','admin','member']));
create policy organizations_update_admin on public.organizations for update to authenticated
using (private.has_org_role(id,array['owner','admin'])) with check (private.has_org_role(id,array['owner','admin']));
create policy org_members_select on public.organization_members for select to authenticated
using (user_id=(select auth.uid()) or private.has_org_role(organization_id,array['owner','admin']));
create policy org_members_manage on public.organization_members for all to authenticated
using (private.has_org_role(organization_id,array['owner','admin'])) with check (private.has_org_role(organization_id,array['owner','admin']));
create policy org_policy_admin_read on public.organization_policies for select to authenticated
using (private.has_org_role(organization_id,array['owner','admin']));
create policy org_policy_admin_write on public.organization_policies for all to authenticated
using (private.has_org_role(organization_id,array['owner','admin'])) with check (private.has_org_role(organization_id,array['owner','admin']));

create policy workspaces_select_member on public.workspaces for select to authenticated using (private.is_workspace_member(id));
create policy workspaces_insert_owner on public.workspaces for insert to authenticated with check (created_by=(select auth.uid()));
create policy workspaces_update_admin on public.workspaces for update to authenticated using (private.has_workspace_role(id,array['owner','admin'])) with check (private.has_workspace_role(id,array['owner','admin']));
create policy workspace_members_select on public.workspace_members for select to authenticated using (private.is_workspace_member(workspace_id));
create policy workspace_members_insert_admin on public.workspace_members for insert to authenticated
with check (private.has_workspace_role(workspace_id,array['owner','admin']) and (role<>'owner' or private.has_workspace_role(workspace_id,array['owner'])));
create policy workspace_members_update_admin on public.workspace_members for update to authenticated
using (private.has_workspace_role(workspace_id,array['owner','admin']))
with check (private.has_workspace_role(workspace_id,array['owner','admin']) and (role<>'owner' or private.has_workspace_role(workspace_id,array['owner'])));
create policy workspace_members_delete_admin on public.workspace_members for delete to authenticated
using (private.has_workspace_role(workspace_id,array['owner','admin']) and (role<>'owner' or private.has_workspace_role(workspace_id,array['owner'])));

create policy boards_select_access on public.boards for select to authenticated using (private.can_access_board(id));
create policy boards_insert_workspace_member on public.boards for insert to authenticated with check (private.is_workspace_member(workspace_id) and created_by=(select auth.uid()));
create policy boards_update_admin on public.boards for update to authenticated using (private.can_admin_board(id)) with check (private.can_admin_board(id));
create policy board_members_select on public.board_members for select to authenticated using (private.can_access_board(board_id));
create policy board_members_insert_admin on public.board_members for insert to authenticated with check (private.can_admin_board(board_id));
create policy board_members_update_admin on public.board_members for update to authenticated using (private.can_admin_board(board_id)) with check (private.can_admin_board(board_id));
create policy board_members_delete_admin on public.board_members for delete to authenticated using (private.can_admin_board(board_id));
create policy board_preferences_read on public.user_board_preferences for select to authenticated using (user_id=(select auth.uid()) and private.can_access_board(board_id));
create policy board_preferences_write on public.user_board_preferences for all to authenticated using (user_id=(select auth.uid()) and private.can_access_board(board_id)) with check (user_id=(select auth.uid()) and private.can_access_board(board_id));
create policy invitations_select_admin on public.invitations for select to authenticated
using ((scope='workspace' and private.has_workspace_role(workspace_id,array['owner','admin'])) or (scope='board' and private.can_admin_board(board_id)));
create policy invitations_insert_admin on public.invitations for insert to authenticated
with check (created_by=(select auth.uid()) and ((scope='workspace' and private.has_workspace_role(workspace_id,array['owner','admin'])) or (scope='board' and private.can_admin_board(board_id))));
create policy invitations_update_admin on public.invitations for update to authenticated
using ((scope='workspace' and private.has_workspace_role(workspace_id,array['owner','admin'])) or (scope='board' and private.can_admin_board(board_id)))
with check ((scope='workspace' and private.has_workspace_role(workspace_id,array['owner','admin'])) or (scope='board' and private.can_admin_board(board_id)));

-- Board-scoped rows inherit access from the board; private Board access is never inferred from workspace role.
create policy lists_select on public.lists for select to authenticated using (private.can_access_board(board_id));
create policy lists_insert on public.lists for insert to authenticated with check (private.can_edit_board(board_id));
create policy lists_update on public.lists for update to authenticated using (private.can_edit_board(board_id)) with check (private.can_edit_board(board_id));
create policy lists_delete on public.lists for delete to authenticated using (private.can_edit_board(board_id));
create policy cards_select on public.cards for select to authenticated using (private.can_access_board(board_id));
create policy cards_insert on public.cards for insert to authenticated with check (private.can_edit_board(board_id) and created_by=(select auth.uid()));
create policy cards_update on public.cards for update to authenticated using (private.can_edit_board(board_id)) with check (private.can_edit_board(board_id));
create policy card_members_read on public.card_members for select to authenticated using (private.can_view_card(card_id));
create policy card_members_write on public.card_members for all to authenticated using (private.can_edit_card(card_id)) with check (private.can_edit_card(card_id));
create policy labels_read on public.labels for select to authenticated using (private.can_access_board(board_id));
create policy labels_write on public.labels for all to authenticated using (private.can_edit_board(board_id)) with check (private.can_edit_board(board_id));
create policy card_labels_read on public.card_labels for select to authenticated using (private.can_access_board(board_id));
create policy card_labels_write on public.card_labels for all to authenticated using (private.can_edit_board(board_id)) with check (private.can_edit_board(board_id));
create policy card_dates_read on public.card_dates for select to authenticated using (private.can_view_card(card_id));
create policy card_dates_write on public.card_dates for all to authenticated using (private.can_edit_card(card_id)) with check (private.can_edit_card(card_id));
create policy recurrence_read on public.recurrence_rules for select to authenticated using (private.can_view_card(card_id));
create policy recurrence_write on public.recurrence_rules for all to authenticated using (private.can_edit_card(card_id)) with check (private.can_edit_card(card_id));
create policy checklists_read on public.checklists for select to authenticated using (private.can_view_card(card_id));
create policy checklists_write on public.checklists for all to authenticated using (private.can_edit_card(card_id)) with check (private.can_edit_card(card_id));
create policy checklist_items_read on public.checklist_items for select to authenticated using (exists(select 1 from public.checklists c where c.id=checklist_id and private.can_view_card(c.card_id)));
create policy checklist_items_write on public.checklist_items for all to authenticated using (exists(select 1 from public.checklists c where c.id=checklist_id and private.can_edit_card(c.card_id))) with check (exists(select 1 from public.checklists c where c.id=checklist_id and private.can_edit_card(c.card_id)));
create policy comments_read on public.comments for select to authenticated using (private.can_view_card(card_id));
create policy comments_insert on public.comments for insert to authenticated with check (private.can_comment_card(card_id) and author_id=(select auth.uid()));
create policy comments_update_own on public.comments for update to authenticated using (author_id=(select auth.uid()) and deleted_at is null and private.can_comment_card(card_id)) with check (author_id=(select auth.uid()) and private.can_comment_card(card_id));
create policy comments_soft_delete_admin on public.comments for update to authenticated using (private.can_admin_board(private.card_board_id(card_id))) with check (private.can_admin_board(private.card_board_id(card_id)));
create policy comment_revisions_read on public.comment_revisions for select to authenticated using (exists(select 1 from public.comments c where c.id=comment_id and private.can_view_card(c.card_id)));
create policy attachments_read on public.attachments for select to authenticated
using ((card_id is not null and private.can_view_card(card_id) and scan_status='clean' and deleted_at is null)
  or (uploaded_by=(select auth.uid()) and scan_status in ('pending','quarantined','failed'))
  or (inbox_item_id is not null and exists(select 1 from public.inbox_items i where i.id=inbox_item_id and i.owner_id=(select auth.uid()))));
create policy attachments_insert on public.attachments for insert to authenticated
with check ((card_id is not null and private.can_edit_card(card_id) and uploaded_by=(select auth.uid())) or
  (inbox_item_id is not null and exists(select 1 from public.inbox_items i where i.id=inbox_item_id and i.owner_id=(select auth.uid()))));
create policy attachments_update on public.attachments for update to authenticated
using ((card_id is not null and private.can_edit_card(card_id)) or (inbox_item_id is not null and exists(select 1 from public.inbox_items i where i.id=inbox_item_id and i.owner_id=(select auth.uid()))))
with check ((card_id is not null and private.can_edit_card(card_id)) or (inbox_item_id is not null and exists(select 1 from public.inbox_items i where i.id=inbox_item_id and i.owner_id=(select auth.uid()))));
create policy attachments_delete on public.attachments for delete to authenticated
using ((card_id is not null and private.can_edit_card(card_id)) or (inbox_item_id is not null and exists(select 1 from public.inbox_items i where i.id=inbox_item_id and i.owner_id=(select auth.uid()))));
create policy mirrors_read on public.card_mirrors for select to authenticated using (private.can_access_board(destination_board_id) and private.can_view_card(source_card_id));
create policy mirrors_create on public.card_mirrors for insert to authenticated with check (private.can_edit_board(destination_board_id) and private.can_view_card(source_card_id) and created_by=(select auth.uid()));
create policy mirrors_remove on public.card_mirrors for delete to authenticated using (private.can_edit_board(destination_board_id) and private.can_view_card(source_card_id));
create policy fields_read on public.field_definitions for select to authenticated using (private.can_access_board(board_id));
create policy fields_admin on public.field_definitions for all to authenticated using (private.can_admin_board(board_id)) with check (private.can_admin_board(board_id));
create policy field_values_read on public.card_field_values for select to authenticated using (private.can_view_card(card_id));
create policy field_values_write on public.card_field_values for all to authenticated using (private.can_edit_card(card_id)) with check (private.can_edit_card(card_id));

create policy collections_read on public.board_collections for select to authenticated using (private.is_workspace_member(workspace_id));
create policy collections_admin on public.board_collections for all to authenticated using (private.has_workspace_role(workspace_id,array['owner','admin'])) with check (private.has_workspace_role(workspace_id,array['owner','admin']));
create policy collection_boards_read on public.collection_boards for select to authenticated
using (private.can_access_board(board_id) and exists(select 1 from public.board_collections c where c.id=collection_id and private.is_workspace_member(c.workspace_id)));
create policy collection_boards_admin on public.collection_boards for all to authenticated
using (private.can_access_board(board_id) and exists(select 1 from public.board_collections c where c.id=collection_id and private.has_workspace_role(c.workspace_id,array['owner','admin'])))
with check (private.can_access_board(board_id) and exists(select 1 from public.board_collections c where c.id=collection_id and private.has_workspace_role(c.workspace_id,array['owner','admin'])));

create policy inbox_read_own on public.inbox_items for select to authenticated using (owner_id=(select auth.uid()));
create policy inbox_insert_own on public.inbox_items for insert to authenticated with check (owner_id=(select auth.uid()));
create policy inbox_update_own on public.inbox_items for update to authenticated using (owner_id=(select auth.uid())) with check (owner_id=(select auth.uid()));
create policy inbox_delete_own on public.inbox_items for delete to authenticated using (owner_id=(select auth.uid()));
create policy saved_searches_own on public.saved_searches for all to authenticated using (user_id=(select auth.uid())) with check (user_id=(select auth.uid()));
create policy saved_views_read on public.saved_views for select to authenticated using (user_id=(select auth.uid()) or (is_shared and board_id is not null and private.can_access_board(board_id)));
create policy saved_views_manage_own on public.saved_views for all to authenticated using (user_id=(select auth.uid())) with check (user_id=(select auth.uid()));
create policy notification_preferences_own on public.notification_preferences for all to authenticated using (user_id=(select auth.uid())) with check (user_id=(select auth.uid()));
create policy notifications_read_own_target_access on public.notifications for select to authenticated
using (recipient_id=(select auth.uid()) and private.can_access_notification_target(target_type,target_id));
create policy notifications_mark_own_read on public.notifications for update to authenticated
using (recipient_id=(select auth.uid()) and private.can_access_notification_target(target_type,target_id))
with check (recipient_id=(select auth.uid()) and private.can_access_notification_target(target_type,target_id));
create policy watches_read_own on public.watch_subscriptions for select to authenticated using (user_id=(select auth.uid()));
create policy watches_manage_own on public.watch_subscriptions for all to authenticated using (user_id=(select auth.uid())) with check (user_id=(select auth.uid()));
create policy calendar_connections_own on public.calendar_connections for all to authenticated using (user_id=(select auth.uid())) with check (user_id=(select auth.uid()));
create policy focus_blocks_own on public.focus_blocks for all to authenticated using (user_id=(select auth.uid())) with check (user_id=(select auth.uid()));

create policy templates_read on public.templates for select to authenticated
using ((workspace_id is null and created_by=(select auth.uid())) or (workspace_id is not null and private.is_workspace_member(workspace_id)));
create policy templates_manage on public.templates for all to authenticated
using ((workspace_id is null and created_by=(select auth.uid())) or (workspace_id is not null and private.has_workspace_role(workspace_id,array['owner','admin'])))
with check ((workspace_id is null and created_by=(select auth.uid())) or (workspace_id is not null and private.has_workspace_role(workspace_id,array['owner','admin'])));
create policy automation_rules_read on public.automation_rules for select to authenticated
using ((board_id is not null and private.can_access_board(board_id)) or (workspace_id is not null and private.has_workspace_role(workspace_id,array['owner','admin'])));
create policy automation_rules_manage on public.automation_rules for all to authenticated
using ((board_id is not null and private.can_admin_board(board_id)) or (workspace_id is not null and private.has_workspace_role(workspace_id,array['owner','admin'])))
with check ((board_id is not null and private.can_admin_board(board_id)) or (workspace_id is not null and private.has_workspace_role(workspace_id,array['owner','admin'])));
create policy automation_runs_read on public.automation_runs for select to authenticated
using (exists(select 1 from public.automation_rules r where r.id=rule_id and
  ((r.board_id is not null and private.can_access_board(r.board_id)) or (r.workspace_id is not null and private.has_workspace_role(r.workspace_id,array['owner','admin'])))));

create policy integrations_read on public.integration_connections for select to authenticated
using (user_id=(select auth.uid()) or (workspace_id is not null and private.has_workspace_role(workspace_id,array['owner','admin'])));
create policy integrations_manage on public.integration_connections for all to authenticated
using (user_id=(select auth.uid()) or (workspace_id is not null and private.has_workspace_role(workspace_id,array['owner','admin'])))
with check (user_id=(select auth.uid()) or (workspace_id is not null and private.has_workspace_role(workspace_id,array['owner','admin'])));
create policy credentials_read_own on public.api_credentials for select to authenticated
using (owner_id=(select auth.uid()) and (workspace_id is null or private.has_workspace_role(workspace_id,array['owner','admin'])));
create policy credentials_manage_own on public.api_credentials for all to authenticated
using (owner_id=(select auth.uid())) with check (owner_id=(select auth.uid()) and (workspace_id is null or private.has_workspace_role(workspace_id,array['owner','admin'])));
create policy webhooks_admin_manage on public.webhooks for all to authenticated using (private.has_workspace_role(workspace_id,array['owner','admin'])) with check (private.has_workspace_role(workspace_id,array['owner','admin']));
create policy webhook_deliveries_admin_read on public.webhook_deliveries for select to authenticated
using (exists(select 1 from public.webhooks w where w.id=webhook_id and private.has_workspace_role(w.workspace_id,array['owner','admin'])));

create policy activity_read_board on public.activity_events for select to authenticated using (private.can_access_board(board_id));
create policy audit_read_admin on public.audit_events for select to authenticated
using ((workspace_id is not null and private.has_workspace_role(workspace_id,array['owner','admin'])) or
  (organization_id is not null and exists(select 1 from public.organization_members m where m.organization_id=audit_events.organization_id and m.user_id=(select auth.uid()) and m.role in ('owner','admin'))));
create policy jobs_read_owner on public.import_export_jobs for select to authenticated
using (owner_id=(select auth.uid()) and (board_id is null or private.can_access_board(board_id)) and (workspace_id is null or private.is_workspace_member(workspace_id)));
create policy jobs_create_owner on public.import_export_jobs for insert to authenticated
with check (owner_id=(select auth.uid()) and (board_id is null or private.can_access_board(board_id)) and (workspace_id is null or private.has_workspace_role(workspace_id,array['owner','admin'])));
create policy billing_plans_active_read on public.billing_plans for select to authenticated using (active);
create policy subscriptions_admin_read on public.subscriptions for select to authenticated using (private.has_workspace_role(workspace_id,array['owner','admin']));
create policy invoices_admin_read on public.invoices for select to authenticated using (private.has_workspace_role(workspace_id,array['owner','admin']));
create policy usage_admin_read on public.usage_records for select to authenticated using (private.has_workspace_role(workspace_id,array['owner','admin']));
create policy ai_requests_read on public.ai_requests for select to authenticated
using (requested_by=(select auth.uid()) or (board_id is not null and private.can_access_board(board_id)) or private.has_workspace_role(workspace_id,array['owner','admin']));
create policy ai_drafts_read on public.ai_drafts for select to authenticated
using (exists(select 1 from public.ai_requests r where r.id=request_id and
  (r.requested_by=(select auth.uid()) or (r.board_id is not null and private.can_access_board(r.board_id)) or private.has_workspace_role(r.workspace_id,array['owner','admin']))));
create policy merge_operations_read on public.merge_operations for select to authenticated using (private.can_access_board(board_id));
create policy workflow_policies_read on public.workflow_policies for select to authenticated using (private.can_access_board(board_id));
create policy workflow_policies_admin on public.workflow_policies for all to authenticated using (private.can_admin_board(board_id)) with check (private.can_admin_board(board_id));
create policy dependencies_read on public.card_dependencies for select to authenticated using (private.can_view_card(predecessor_card_id) and private.can_view_card(successor_card_id));
create policy dependencies_write on public.card_dependencies for all to authenticated using (private.can_edit_card(predecessor_card_id) and private.can_edit_card(successor_card_id)) with check (private.can_edit_card(predecessor_card_id) and private.can_edit_card(successor_card_id));
create policy time_entries_read on public.time_entries for select to authenticated using (private.can_view_card(card_id));
create policy time_entries_write_own on public.time_entries for all to authenticated using (user_id=(select auth.uid()) and private.can_edit_card(card_id)) with check (user_id=(select auth.uid()) and private.can_edit_card(card_id));

-- Server-only writes (no authenticated policy): revisions, audit/outbox, provider delivery,
-- external ID mappings, automation worker runs, AI generation/apply and billing mutations.
-- Keep service_role keys server-side; service_role bypasses RLS.

-- Supabase Storage setup: create a PRIVATE bucket named orbit-attachments in the Dashboard first.
-- Object path format: <workspace_uuid>/<board_uuid>/<card_uuid>/<attachment_uuid>/<filename>.
-- Never modify storage tables directly; Storage API calls are guarded by these policies.
create or replace function private.attachment_object_allowed(p_name text,p_write boolean)
returns boolean language plpgsql stable security definer set search_path = '' as $$
declare f text[];
begin
  f:=storage.foldername(p_name);
  if coalesce(array_length(f,1),0)<>4 then return false; end if;
  if f[1]!~*'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  or f[2]!~*'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  or f[3]!~*'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then return false; end if;
  if not exists(select 1 from public.boards b join public.cards c on c.board_id=b.id
    where b.id=f[2]::uuid and b.workspace_id=f[1]::uuid and c.id=f[3]::uuid) then return false; end if;
  if p_write then return private.can_edit_board(f[2]::uuid); end if;
  return private.can_access_board(f[2]::uuid);
end; $$;
revoke all on function private.attachment_object_allowed(text,boolean) from public,anon;
grant execute on function private.attachment_object_allowed(text,boolean) to authenticated;
create policy orbit_attachments_read on storage.objects for select to authenticated
using(bucket_id='orbit-attachments' and private.attachment_object_allowed(name,false));
create policy orbit_attachments_upload on storage.objects for insert to authenticated
with check(bucket_id='orbit-attachments' and private.attachment_object_allowed(name,true));
create policy orbit_attachments_replace on storage.objects for update to authenticated
using(bucket_id='orbit-attachments' and private.attachment_object_allowed(name,true))
with check(bucket_id='orbit-attachments' and private.attachment_object_allowed(name,true));
create policy orbit_attachments_remove on storage.objects for delete to authenticated
using(bucket_id='orbit-attachments' and private.attachment_object_allowed(name,true));

commit;

