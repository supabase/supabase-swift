create policy "Allow all" on "storage"."objects" as PERMISSIVE
    for all to public
        using (true)
        with check (true);

create policy "Allow all" on "storage"."buckets" as PERMISSIVE
    for all to public
        using (true)
        with check (true);
