
create or replace function public.link_event_participant_to_member()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.member_id is null then
    select m.id
      into new.member_id
      from public.members m
     where lower(btrim(m.display_name)) = lower(btrim(new.display_name))
       and lower(btrim(m.family)) = lower(btrim(coalesce(new.family, '')))
     order by m.created_at
     limit 1;
  end if;
  return new;
end;
$$;

drop trigger if exists event_participants_link_member on public.event_participants;
create trigger event_participants_link_member
before insert or update of display_name, family, member_id
on public.event_participants
for each row execute function public.link_event_participant_to_member();
