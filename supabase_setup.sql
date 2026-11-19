-- Escola José Bento de Carvalho Filho
-- Execute todo este arquivo no Supabase > SQL Editor > New query.
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  email text,
  role text not null default 'professor' check (role in ('professor','coordinator','admin')),
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, email, role)
  values (new.id, coalesce(new.raw_user_meta_data->>'full_name',''), new.email, 'professor')
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
for each row execute procedure public.handle_new_user();

create or replace function public.current_role()
returns text language sql stable security definer set search_path = public
as $$
  select role from public.profiles where id = auth.uid() and is_active = true
$$;

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public
as $$
  select coalesce(public.current_role() = 'admin', false)
$$;

create or replace function public.is_staff()
returns boolean language sql stable security definer set search_path = public
as $$
  select coalesce(public.current_role() in ('admin','coordinator'), false)
$$;

create table if not exists public.equipment (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  quantity integer not null default 0 check (quantity >= 0),
  icon text not null default '📦',
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.bookings (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id),
  requester_name text not null default 'Usuário',
  equipment_id uuid not null references public.equipment(id),
  quantity integer not null check (quantity > 0),
  booking_date date not null,
  start_time time not null,
  end_time time not null,
  purpose text not null,
  status text not null default 'confirmed' check (status in ('confirmed','cancelled')),
  picked_up_at timestamptz,
  returned_at timestamptz,
  created_at timestamptz not null default now(),
  constraint booking_time_valid check (end_time > start_time)
);

create index if not exists bookings_equipment_date_idx
on public.bookings(equipment_id, booking_date, start_time, end_time)
where status = 'confirmed';

alter table public.profiles enable row level security;
alter table public.equipment enable row level security;
alter table public.bookings enable row level security;

drop policy if exists "profiles_select_school" on public.profiles;
create policy "profiles_select_school" on public.profiles for select to authenticated
using (id = auth.uid() or public.is_admin());

drop policy if exists "profiles_admin_update" on public.profiles;
create policy "profiles_admin_update" on public.profiles for update to authenticated
using (public.is_admin()) with check (public.is_admin());

drop policy if exists "equipment_read_authenticated" on public.equipment;
create policy "equipment_read_authenticated" on public.equipment for select to authenticated
using (true);

drop policy if exists "equipment_admin_insert" on public.equipment;
create policy "equipment_admin_insert" on public.equipment for insert to authenticated
with check (public.is_admin());

drop policy if exists "equipment_admin_update" on public.equipment;
create policy "equipment_admin_update" on public.equipment for update to authenticated
using (public.is_admin()) with check (public.is_admin());

drop policy if exists "equipment_admin_delete" on public.equipment;
create policy "equipment_admin_delete" on public.equipment for delete to authenticated
using (public.is_admin());

drop policy if exists "bookings_read_school" on public.bookings;
create policy "bookings_read_school" on public.bookings for select to authenticated
using (true);

drop policy if exists "bookings_insert_own" on public.bookings;
create policy "bookings_insert_own" on public.bookings for insert to authenticated
with check (user_id = auth.uid());

drop policy if exists "bookings_staff_update" on public.bookings;
create policy "bookings_staff_update" on public.bookings for update to authenticated
using (public.is_staff()) with check (public.is_staff());

-- Reserva atômica: bloqueia o item durante a verificação para impedir
-- que duas pessoas confirmem simultaneamente as últimas unidades.
create or replace function public.create_booking(
  p_equipment_id uuid,
  p_quantity integer,
  p_booking_date date,
  p_start_time time,
  p_end_time time,
  p_purpose text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_equipment public.equipment%rowtype;
  v_reserved integer;
  v_id uuid;
  v_name text;
begin
  if auth.uid() is null then raise exception 'Faça login para reservar.'; end if;
  if p_quantity < 1 or p_end_time <= p_start_time then
    raise exception 'Quantidade ou horário inválido.';
  end if;

  select * into v_equipment from public.equipment
  where id = p_equipment_id and is_active = true
  for update;

  if not found then raise exception 'Equipamento não encontrado ou inativo.'; end if;

  select coalesce(sum(quantity),0) into v_reserved
  from public.bookings
  where equipment_id = p_equipment_id
    and booking_date = p_booking_date
    and status = 'confirmed'
    and start_time < p_end_time
    and end_time > p_start_time;

  if p_quantity > v_equipment.quantity - v_reserved then
    raise exception 'Quantidade indisponível. Restam % unidade(s).',
      greatest(v_equipment.quantity - v_reserved,0);
  end if;

  select coalesce(full_name,'Usuário') into v_name from public.profiles where id = auth.uid();

  insert into public.bookings(user_id,requester_name,equipment_id,quantity,booking_date,start_time,end_time,purpose)
  values(auth.uid(),coalesce(v_name,'Usuário'),p_equipment_id,p_quantity,p_booking_date,p_start_time,p_end_time,trim(p_purpose))
  returning id into v_id;

  return v_id;
end;
$$;

revoke all on function public.create_booking(uuid,integer,date,time,time,text) from public;
grant execute on function public.create_booking(uuid,integer,date,time,time,text) to authenticated;

grant usage on schema public to authenticated;
grant select on public.profiles, public.equipment, public.bookings to authenticated;
grant update on public.profiles to authenticated;
grant insert, update, delete on public.equipment to authenticated;
grant insert, update on public.bookings to authenticated;

insert into public.equipment(name,quantity,icon) values
 ('Computadores',12,'💻'),
 ('Tablets',20,'📱'),
 ('Data show',4,'📽️'),
 ('Caixas de som',3,'🔊')
on conflict (name) do nothing;

-- Depois que o primeiro usuário criar conta e confirmar o e-mail:
-- substitua pelo e-mail do responsável e execute para torná-lo administrador:
-- update public.profiles set role = 'admin' where email = 'direcao@escola.com';

-- Para impedir cadastro público depois de criar os usuários iniciais:
-- Supabase Dashboard > Authentication > Settings > desative "Allow new users to sign up".
