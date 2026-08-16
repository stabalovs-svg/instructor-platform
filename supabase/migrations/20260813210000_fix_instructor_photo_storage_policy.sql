-- Store each instructor photo under the authenticated Auth user id.

drop policy if exists instructor_photo_owner_insert on storage.objects;
create policy instructor_photo_owner_insert on storage.objects
for insert to authenticated
with check (
  bucket_id = 'instructor-photos'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists instructor_photo_owner_update on storage.objects;
create policy instructor_photo_owner_update on storage.objects
for update to authenticated
using (
  bucket_id = 'instructor-photos'
  and (storage.foldername(name))[1] = auth.uid()::text
)
with check (
  bucket_id = 'instructor-photos'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists instructor_photo_owner_select on storage.objects;
create policy instructor_photo_owner_select on storage.objects
for select to authenticated
using (
  bucket_id = 'instructor-photos'
  and (storage.foldername(name))[1] = auth.uid()::text
);

