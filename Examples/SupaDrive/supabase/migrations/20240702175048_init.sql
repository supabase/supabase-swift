INSERT INTO storage.buckets(id, name)
    VALUES ('main', 'main');

CREATE POLICY "Allow authenticated access to own folder" ON storage.objects
    FOR ALL TO authenticated
        USING (bucket_id = 'main'
            AND (storage.foldername(name))[1] =(
                SELECT
                    auth.uid()::text))
                WITH CHECK (bucket_id = 'main'
                AND (storage.foldername(name))[1] =(
                    SELECT
                        auth.uid()::text));

