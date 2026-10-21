-- Keep one policy per table/action where different read and write scopes are needed.
-- This preserves the role predicates while avoiding redundant permissive policies.
begin;

drop policy credentials_manage_own on public.api_credentials;
create policy credentials_insert_own on public.api_credentials for insert to authenticated
with check(owner_id=(select auth.uid()) and (workspace_id is null or private.has_workspace_role(workspace_id,array['owner','admin'])));
create policy credentials_update_own on public.api_credentials for update to authenticated
using(owner_id=(select auth.uid()))
with check(owner_id=(select auth.uid()) and (workspace_id is null or private.has_workspace_role(workspace_id,array['owner','admin'])));
create policy credentials_delete_own on public.api_credentials for delete to authenticated using(owner_id=(select auth.uid()));

drop policy automation_rules_manage on public.automation_rules;
create policy automation_rules_insert on public.automation_rules for insert to authenticated
with check((board_id is not null and private.can_admin_board(board_id)) or (workspace_id is not null and private.has_workspace_role(workspace_id,array['owner','admin'])));
create policy automation_rules_update on public.automation_rules for update to authenticated
using((board_id is not null and private.can_admin_board(board_id)) or (workspace_id is not null and private.has_workspace_role(workspace_id,array['owner','admin'])))
with check((board_id is not null and private.can_admin_board(board_id)) or (workspace_id is not null and private.has_workspace_role(workspace_id,array['owner','admin'])));
create policy automation_rules_delete on public.automation_rules for delete to authenticated
using((board_id is not null and private.can_admin_board(board_id)) or (workspace_id is not null and private.has_workspace_role(workspace_id,array['owner','admin'])));

drop policy collections_admin on public.board_collections;
create policy collections_insert on public.board_collections for insert to authenticated with check(private.has_workspace_role(workspace_id,array['owner','admin']));
create policy collections_update on public.board_collections for update to authenticated using(private.has_workspace_role(workspace_id,array['owner','admin'])) with check(private.has_workspace_role(workspace_id,array['owner','admin']));
create policy collections_delete on public.board_collections for delete to authenticated using(private.has_workspace_role(workspace_id,array['owner','admin']));

drop policy card_dates_write on public.card_dates;
create policy card_dates_insert on public.card_dates for insert to authenticated with check(private.can_edit_card(card_id));
create policy card_dates_update on public.card_dates for update to authenticated using(private.can_edit_card(card_id)) with check(private.can_edit_card(card_id));
create policy card_dates_delete on public.card_dates for delete to authenticated using(private.can_edit_card(card_id));

drop policy dependencies_write on public.card_dependencies;
create policy dependencies_insert on public.card_dependencies for insert to authenticated with check(private.can_edit_card(predecessor_card_id) and private.can_edit_card(successor_card_id));
create policy dependencies_update on public.card_dependencies for update to authenticated using(private.can_edit_card(predecessor_card_id) and private.can_edit_card(successor_card_id)) with check(private.can_edit_card(predecessor_card_id) and private.can_edit_card(successor_card_id));
create policy dependencies_delete on public.card_dependencies for delete to authenticated using(private.can_edit_card(predecessor_card_id) and private.can_edit_card(successor_card_id));

drop policy field_values_write on public.card_field_values;
create policy field_values_insert on public.card_field_values for insert to authenticated with check(private.can_edit_card(card_id));
create policy field_values_update on public.card_field_values for update to authenticated using(private.can_edit_card(card_id)) with check(private.can_edit_card(card_id));
create policy field_values_delete on public.card_field_values for delete to authenticated using(private.can_edit_card(card_id));

drop policy card_labels_write on public.card_labels;
create policy card_labels_insert on public.card_labels for insert to authenticated with check(private.can_edit_board(board_id));
create policy card_labels_update on public.card_labels for update to authenticated using(private.can_edit_board(board_id)) with check(private.can_edit_board(board_id));
create policy card_labels_delete on public.card_labels for delete to authenticated using(private.can_edit_board(board_id));

drop policy card_members_write on public.card_members;
create policy card_members_insert on public.card_members for insert to authenticated with check(private.can_edit_card(card_id));
create policy card_members_update on public.card_members for update to authenticated using(private.can_edit_card(card_id)) with check(private.can_edit_card(card_id));
create policy card_members_delete on public.card_members for delete to authenticated using(private.can_edit_card(card_id));

drop policy checklist_items_write on public.checklist_items;
create policy checklist_items_insert on public.checklist_items for insert to authenticated with check(exists(select 1 from public.checklists c where c.id=checklist_id and private.can_edit_card(c.card_id)));
create policy checklist_items_update on public.checklist_items for update to authenticated using(exists(select 1 from public.checklists c where c.id=checklist_id and private.can_edit_card(c.card_id))) with check(exists(select 1 from public.checklists c where c.id=checklist_id and private.can_edit_card(c.card_id)));
create policy checklist_items_delete on public.checklist_items for delete to authenticated using(exists(select 1 from public.checklists c where c.id=checklist_id and private.can_edit_card(c.card_id)));

drop policy checklists_write on public.checklists;
create policy checklists_insert on public.checklists for insert to authenticated with check(private.can_edit_card(card_id));
create policy checklists_update on public.checklists for update to authenticated using(private.can_edit_card(card_id)) with check(private.can_edit_card(card_id));
create policy checklists_delete on public.checklists for delete to authenticated using(private.can_edit_card(card_id));

drop policy collection_boards_admin on public.collection_boards;
create policy collection_boards_insert on public.collection_boards for insert to authenticated with check(private.can_access_board(board_id) and exists(select 1 from public.board_collections c where c.id=collection_id and private.has_workspace_role(c.workspace_id,array['owner','admin'])));
create policy collection_boards_update on public.collection_boards for update to authenticated using(private.can_access_board(board_id) and exists(select 1 from public.board_collections c where c.id=collection_id and private.has_workspace_role(c.workspace_id,array['owner','admin']))) with check(private.can_access_board(board_id) and exists(select 1 from public.board_collections c where c.id=collection_id and private.has_workspace_role(c.workspace_id,array['owner','admin'])));
create policy collection_boards_delete on public.collection_boards for delete to authenticated using(private.can_access_board(board_id) and exists(select 1 from public.board_collections c where c.id=collection_id and private.has_workspace_role(c.workspace_id,array['owner','admin'])));

drop policy comments_update_own on public.comments;
drop policy comments_soft_delete_admin on public.comments;
create policy comments_update_author_or_admin on public.comments for update to authenticated
using((author_id=(select auth.uid()) and deleted_at is null and private.can_comment_card(card_id)) or private.can_admin_board(private.card_board_id(card_id)))
with check((author_id=(select auth.uid()) and private.can_comment_card(card_id)) or private.can_admin_board(private.card_board_id(card_id)));

drop policy fields_admin on public.field_definitions;
create policy fields_insert_admin on public.field_definitions for insert to authenticated with check(private.can_admin_board(board_id));
create policy fields_update_admin on public.field_definitions for update to authenticated using(private.can_admin_board(board_id)) with check(private.can_admin_board(board_id));
create policy fields_delete_admin on public.field_definitions for delete to authenticated using(private.can_admin_board(board_id));

drop policy integrations_manage on public.integration_connections;
create policy integrations_insert on public.integration_connections for insert to authenticated
with check(user_id=(select auth.uid()) or (workspace_id is not null and private.has_workspace_role(workspace_id,array['owner','admin'])));
create policy integrations_update on public.integration_connections for update to authenticated
using(user_id=(select auth.uid()) or (workspace_id is not null and private.has_workspace_role(workspace_id,array['owner','admin'])))
with check(user_id=(select auth.uid()) or (workspace_id is not null and private.has_workspace_role(workspace_id,array['owner','admin'])));
create policy integrations_delete on public.integration_connections for delete to authenticated
using(user_id=(select auth.uid()) or (workspace_id is not null and private.has_workspace_role(workspace_id,array['owner','admin'])));

drop policy labels_write on public.labels;
create policy labels_insert on public.labels for insert to authenticated with check(private.can_edit_board(board_id));
create policy labels_update on public.labels for update to authenticated using(private.can_edit_board(board_id)) with check(private.can_edit_board(board_id));
create policy labels_delete on public.labels for delete to authenticated using(private.can_edit_board(board_id));

drop policy org_members_manage on public.organization_members;
create policy org_members_insert on public.organization_members for insert to authenticated with check(private.has_org_role(organization_id,array['owner','admin']));
create policy org_members_update on public.organization_members for update to authenticated using(private.has_org_role(organization_id,array['owner','admin'])) with check(private.has_org_role(organization_id,array['owner','admin']));
create policy org_members_delete on public.organization_members for delete to authenticated using(private.has_org_role(organization_id,array['owner','admin']));

drop policy org_policy_admin_write on public.organization_policies;
create policy org_policy_admin_insert on public.organization_policies for insert to authenticated with check(private.has_org_role(organization_id,array['owner','admin']));
create policy org_policy_admin_update on public.organization_policies for update to authenticated using(private.has_org_role(organization_id,array['owner','admin'])) with check(private.has_org_role(organization_id,array['owner','admin']));
create policy org_policy_admin_delete on public.organization_policies for delete to authenticated using(private.has_org_role(organization_id,array['owner','admin']));

drop policy recurrence_write on public.recurrence_rules;
create policy recurrence_insert on public.recurrence_rules for insert to authenticated with check(private.can_edit_card(card_id));
create policy recurrence_update on public.recurrence_rules for update to authenticated using(private.can_edit_card(card_id)) with check(private.can_edit_card(card_id));
create policy recurrence_delete on public.recurrence_rules for delete to authenticated using(private.can_edit_card(card_id));

drop policy saved_views_manage_own on public.saved_views;
create policy saved_views_insert_own on public.saved_views for insert to authenticated with check(user_id=(select auth.uid()));
create policy saved_views_update_own on public.saved_views for update to authenticated using(user_id=(select auth.uid())) with check(user_id=(select auth.uid()));
create policy saved_views_delete_own on public.saved_views for delete to authenticated using(user_id=(select auth.uid()));

drop policy templates_manage on public.templates;
create policy templates_insert on public.templates for insert to authenticated
with check((workspace_id is null and created_by=(select auth.uid())) or (workspace_id is not null and private.has_workspace_role(workspace_id,array['owner','admin'])));
create policy templates_update on public.templates for update to authenticated
using((workspace_id is null and created_by=(select auth.uid())) or (workspace_id is not null and private.has_workspace_role(workspace_id,array['owner','admin'])))
with check((workspace_id is null and created_by=(select auth.uid())) or (workspace_id is not null and private.has_workspace_role(workspace_id,array['owner','admin'])));
create policy templates_delete on public.templates for delete to authenticated
using((workspace_id is null and created_by=(select auth.uid())) or (workspace_id is not null and private.has_workspace_role(workspace_id,array['owner','admin'])));

drop policy time_entries_write_own on public.time_entries;
create policy time_entries_insert_own on public.time_entries for insert to authenticated with check(user_id=(select auth.uid()) and private.can_edit_card(card_id));
create policy time_entries_update_own on public.time_entries for update to authenticated using(user_id=(select auth.uid()) and private.can_edit_card(card_id)) with check(user_id=(select auth.uid()) and private.can_edit_card(card_id));
create policy time_entries_delete_own on public.time_entries for delete to authenticated using(user_id=(select auth.uid()) and private.can_edit_card(card_id));

drop policy board_preferences_write on public.user_board_preferences;
create policy board_preferences_insert on public.user_board_preferences for insert to authenticated with check(user_id=(select auth.uid()) and private.can_access_board(board_id));
create policy board_preferences_update on public.user_board_preferences for update to authenticated using(user_id=(select auth.uid()) and private.can_access_board(board_id)) with check(user_id=(select auth.uid()) and private.can_access_board(board_id));
create policy board_preferences_delete on public.user_board_preferences for delete to authenticated using(user_id=(select auth.uid()) and private.can_access_board(board_id));

drop policy watches_manage_own on public.watch_subscriptions;
create policy watches_insert_own on public.watch_subscriptions for insert to authenticated with check(user_id=(select auth.uid()));
create policy watches_update_own on public.watch_subscriptions for update to authenticated using(user_id=(select auth.uid())) with check(user_id=(select auth.uid()));
create policy watches_delete_own on public.watch_subscriptions for delete to authenticated using(user_id=(select auth.uid()));

drop policy workflow_policies_admin on public.workflow_policies;
create policy workflow_policies_insert_admin on public.workflow_policies for insert to authenticated with check(private.can_admin_board(board_id));
create policy workflow_policies_update_admin on public.workflow_policies for update to authenticated using(private.can_admin_board(board_id)) with check(private.can_admin_board(board_id));
create policy workflow_policies_delete_admin on public.workflow_policies for delete to authenticated using(private.can_admin_board(board_id));

commit;
