-- NotKSP Supabase Database Schema
-- Paste this script into your Supabase SQL Editor (https://supabase.com) and click Run.

-- 1. Profiles Table (syncs user details with auth.users)
create table if not exists public.profiles (
  id uuid references auth.users on delete cascade primary key,
  email text not null unique,
  name text,
  role text not null default 'customer',
  created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

alter table public.profiles enable row level security;

-- Drop existing policies if any
drop policy if exists "Allow users to read their own profile" on public.profiles;
drop policy if exists "Allow users to update their own profile" on public.profiles;
drop policy if exists "Allow admins to read all profiles" on public.profiles;

create policy "Allow users to read their own profile" on public.profiles 
  for select using (auth.uid() = id);
create policy "Allow users to update their own profile" on public.profiles 
  for update using (auth.uid() = id);
create policy "Allow admins to read all profiles" on public.profiles 
  for select using (
    (select role from public.profiles where id = auth.uid()) = 'admin' or auth.jwt() ->> 'email' = 'admin@notksp.co.il'
  );

-- 2. Products Table
create table if not exists public.products (
  id text primary key,
  name text not null,
  price numeric not null,
  category text not null,
  image_url text,
  description text,
  stock_quantity integer not null default 0,
  specifications jsonb not null default '{}'::jsonb,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

alter table public.products enable row level security;

drop policy if exists "Allow public read access to products" on public.products;
drop policy if exists "Allow admin write access to products" on public.products;

create policy "Allow public read access to products" on public.products 
  for select using (true);
create policy "Allow admin write access to products" on public.products 
  for all using (
    (select role from public.profiles where id = auth.uid()) = 'admin' or auth.jwt() ->> 'email' = 'admin@notksp.co.il'
  );

-- 3. Orders Table
create table if not exists public.orders (
  id text primary key,
  customer_name text not null,
  customer_phone text not null,
  customer_email text,
  customer_address text not null,
  is_guest boolean not null default false,
  items jsonb not null,
  total numeric not null,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

alter table public.orders enable row level security;

drop policy if exists "Allow users to read their own orders" on public.orders;
drop policy if exists "Allow admins to read/write all orders" on public.orders;
drop policy if exists "Allow public to insert orders" on public.orders;

create policy "Allow users to read their own orders" on public.orders 
  for select using (customer_email = auth.jwt() ->> 'email');
create policy "Allow admins to read/write all orders" on public.orders 
  for all using (
    (select role from public.profiles where id = auth.uid()) = 'admin' or auth.jwt() ->> 'email' = 'admin@notksp.co.il'
  );
create policy "Allow public to insert orders" on public.orders 
  for insert with check (true);

-- 4. Requests Table (Replenishment requests)
create table if not exists public.requests (
  id text primary key,
  product_name text not null,
  note text,
  email text not null,
  status text not null default 'open',
  created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

alter table public.requests enable row level security;

drop policy if exists "Allow users to read their own requests" on public.requests;
drop policy if exists "Allow anyone to insert a request" on public.requests;
drop policy if exists "Allow admins to manage all requests" on public.requests;

create policy "Allow users to read their own requests" on public.requests 
  for select using (email = auth.jwt() ->> 'email');
create policy "Allow anyone to insert a request" on public.requests 
  for insert with check (true);
create policy "Allow admins to manage all requests" on public.requests 
  for all using (
    (select role from public.profiles where id = auth.uid()) = 'admin' or auth.jwt() ->> 'email' = 'admin@notksp.co.il'
  );

-- 5. Wishlists Table
create table if not exists public.wishlists (
  user_id uuid references auth.users on delete cascade primary key,
  product_ids jsonb not null default '[]'::jsonb,
  updated_at timestamp with time zone default timezone('utc'::text, now()) not null
);

alter table public.wishlists enable row level security;

drop policy if exists "Allow users to manage their own wishlist" on public.wishlists;

create policy "Allow users to manage their own wishlist" on public.wishlists 
  for all using (auth.uid() = user_id);

-- 6. Trigger to automatically create a profile row for new users
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, email, name, role)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'name', 'משתמש חדש'),
    case when new.email = 'admin@notksp.co.il' then 'admin' else 'customer' end
  );
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();
