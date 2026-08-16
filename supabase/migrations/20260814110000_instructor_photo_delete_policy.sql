-- Allow an authenticated instructor to delete only their own profile photo.

drop policy if exists instructor_photo_owner_delete on storage.objects;
create policy instructor_photo_owner_delete on storage.objects
for delete to authenticated
using (
  bucket_id = 'instructor-photos'
  and (storage.foldername(name))[1] = auth.uid()::text
);

