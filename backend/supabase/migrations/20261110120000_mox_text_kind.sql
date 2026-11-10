-- Lets the slot carry plain text as well as files (#101). A text item is
-- stored like a file (a UTF-8 object named `current`), and receivers put it
-- on the clipboard as text instead of saving a file. Idempotent.
alter table mox.current_file drop constraint if exists current_file_kind;
alter table mox.current_file add constraint current_file_kind
    check (kind in ('file', 'bundle', 'text'));

alter table mox.current_file drop constraint if exists current_file_item_count;
alter table mox.current_file add constraint current_file_item_count check (
    (kind in ('file', 'text') and item_count = 1) or (kind = 'bundle' and item_count >= 2)
);
